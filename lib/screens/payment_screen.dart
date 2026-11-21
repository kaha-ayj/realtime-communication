import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';
import '../models/miomipay_charge.dart';
import '../models/order.dart';
import '../providers/app_provider.dart';
import '../services/order.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';
import 'receipt_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.order});
  final PosOrder order;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with TickerProviderStateMixin {
  MiomiPayCharge? _charge;
  String? _error;
  bool _loadingCharge = true;
  bool _polling = false;
  bool? _serverOnline;
  Timer? _pollTimer;
  int _elapsedSeconds = 0;
  Timer? _clockTimer;

  /// True setelah kasir menyalin link gambar QR ke clipboard.
  bool _linkCopied = false;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _checkServer();
    _createCharge();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    final online = await context.read<AppProvider>().miomiPayService.ping();
    if (!mounted) return;
    setState(() => _serverOnline = online);
  }

  Future<void> _createCharge() async {
    final provider = context.read<AppProvider>();
    try {
      final charge = await provider.miomiPayService.createCharge(
        reference: widget.order.code,
        amount: widget.order.total,
        description: 'POS · ${widget.order.code}',
      );

      if (!mounted) return;

      await provider.orderService.attachPayment(
        orderId: widget.order.id,
        reference: charge.reference,
        isSimulated: charge.offlineSimulation || Config.miomiPaySandbox,
      );

      setState(() {
        _charge = charge;
        _loadingCharge = false;
      });

      _startPolling();
      _startClock();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal membuat tagihan: $e';
        _loadingCharge = false;
      });
    }
  }

  void _startPolling() {
    if (_charge == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  void _startClock() {
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() => _elapsedSeconds++) : null,
    );
  }

  Future<void> _checkStatus() async {
    if (_charge == null || _polling) return;
    if (_charge!.offlineSimulation) return;
    _polling = true;

    try {
      final status = await context
          .read<AppProvider>()
          .miomiPayService
          .checkStatus(_charge!.reference);

      if (!mounted) return;
      setState(() => _charge = _charge!.copyWith(status: status));

      if (_charge!.isPaid) {
        _onPaymentSuccess();
      } else if (status == MiomiPayStatus.expired ||
          status == MiomiPayStatus.failed) {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // abaikan error polling
    } finally {
      _polling = false;
    }
  }

  Future<void> _onPaymentSuccess() async {
    _pollTimer?.cancel();
    _clockTimer?.cancel();

    final provider = context.read<AppProvider>();
    final isSimulated = _charge!.offlineSimulation || Config.miomiPaySandbox;

    try {
      await provider.orderService.markPaid(
        orderId: widget.order.id,
        reference: _charge!.reference,
        isSimulated: isSimulated,
      );
    } catch (_) {}

    if (!mounted) return;

    final paidOrder = widget.order.copyWith(
      status: OrderStatus.paid,
      paidAt: DateTime.now(),
      paymentReference: _charge!.reference,
      isSimulatedPayment: isSimulated,
    );

    provider.clearCart();

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ReceiptScreen(order: paidOrder)),
    );
  }

  Future<void> _cancelOrder() async {
    final provider = context.read<AppProvider>();
    final orderService = provider.orderService;
    final nav = Navigator.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Pesanan?'),
        content: const Text(
          'Pesanan akan dibatalkan dan tidak dapat diproses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PosColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );

    if (ok == true) {
      _pollTimer?.cancel();
      _clockTimer?.cancel();
      try {
        await orderService.markCancelled(widget.order.id);
      } catch (_) {}
      if (_charge != null && !_charge!.offlineSimulation) {
        await provider.miomiPayService.cancelCharge(_charge!.reference);
      }
      if (mounted) nav.pop();
    }
  }

  /// Menyalin link simulasi pembayaran MiomiPay ke clipboard.
  ///
  /// Prioritas: checkout_url → qr_image_url → snap_token → reference.
  /// Semua format ini diterima MiomiPay sebagai input simulasi pembayaran.
  Future<void> _copyQrLink() async {
    if (_charge == null) return;

    final link = _charge!.checkoutUrl ??
        _charge!.qrImageUrl ??
        _charge!.snapToken ??
        _charge!.reference;

    await Clipboard.setData(ClipboardData(text: link));

    if (!mounted) return;
    setState(() => _linkCopied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Link disalin! Paste di MiomiPay untuk menyelesaikan pembayaran.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: PosColors.success,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran QRIS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _cancelOrder,
        ),
      ),
      body: _loadingCharge
          ? const _LoadingView()
          : _error != null
          ? _ErrorView(
              error: _error!,
              onRetry: () {
                setState(() {
                  _loadingCharge = true;
                  _error = null;
                });
                _createCharge();
              },
            )
          : _charge!.isPaid
          ? const _PaidView()
          : _charge!.status == MiomiPayStatus.expired ||
                _charge!.status == MiomiPayStatus.failed
          ? _FinishedView(
              status: _charge!.status,
              onRetry: () {
                setState(() {
                  _loadingCharge = true;
                  _error = null;
                });
                _createCharge();
              },
              onCancel: _cancelOrder,
            )
          : _QrisView(
              charge: _charge!,
              order: widget.order,
              elapsedSeconds: _elapsedSeconds,
              serverOnline: _serverOnline,
              pulseCtrl: _pulseCtrl,
              linkCopied: _linkCopied,
              onCancel: _cancelOrder,
              onCopyQrLink: _copyQrLink,
            ),
    );
  }
}

// ── Loading ──────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Membuat tagihan QRIS…',
            style: TextStyle(color: PosColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Error ────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: PosColors.danger,
            ),
            const SizedBox(height: 16),
            const Text(
              'Gagal membuat tagihan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PosColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            PosButton(
              label: 'Coba Lagi',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Paid ─────────────────────────────────────────────────────────────────────

class _PaidView extends StatelessWidget {
  const _PaidView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 80, color: PosColors.success),
          SizedBox(height: 20),
          Text(
            'Pembayaran Berhasil!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: PosColors.success,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Mengalihkan ke struk…',
            style: TextStyle(color: PosColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Finished (expired / failed) ───────────────────────────────────────────────

class _FinishedView extends StatelessWidget {
  const _FinishedView({
    required this.status,
    required this.onRetry,
    required this.onCancel,
  });

  final MiomiPayStatus status;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final expired = status == MiomiPayStatus.expired;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expired ? Icons.timer_off_outlined : Icons.error_outline_rounded,
              size: 72,
              color: PosColors.danger,
            ),
            const SizedBox(height: 18),
            Text(
              expired ? 'Tagihan Kedaluwarsa' : 'Pembayaran Gagal',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: PosColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              expired
                  ? 'Waktu pembayaran habis. Buat tagihan baru untuk melanjutkan.'
                  : 'Transaksi tidak dapat diproses. Silakan coba lagi.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: PosColors.textMuted, fontSize: 13.5),
            ),
            const SizedBox(height: 26),
            PosButton(
              label: 'Buat Tagihan Baru',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
            const SizedBox(height: 10),
            PosButton(
              label: 'Batalkan Pesanan',
              icon: Icons.close_rounded,
              outlined: true,
              danger: true,
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

// ── QRIS View ─────────────────────────────────────────────────────────────────

class _QrisView extends StatelessWidget {
  const _QrisView({
    required this.charge,
    required this.order,
    required this.elapsedSeconds,
    required this.serverOnline,
    required this.pulseCtrl,
    required this.linkCopied,
    required this.onCancel,
    required this.onCopyQrLink,
  });

  final MiomiPayCharge charge;
  final PosOrder order;
  final int elapsedSeconds;
  final bool? serverOnline;
  final AnimationController pulseCtrl;
  final bool linkCopied;
  final VoidCallback onCancel;
  final VoidCallback onCopyQrLink;

  String get _elapsed {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // ── Header nominal ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: PosColors.primarySoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Text(
                'Total Pembayaran',
                style: TextStyle(color: PosColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                formatCurrency(order.total),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: PosColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Kode: ${order.code}',
                style: const TextStyle(fontSize: 12, color: PosColors.textMuted),
              ),
              const SizedBox(height: 10),
              // Badge status koneksi MiomiPay
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: serverOnline == true
                      ? PosColors.successSoft
                      : PosColors.warningSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: serverOnline == true
                            ? PosColors.success
                            : PosColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      serverOnline == null
                          ? 'Memeriksa koneksi…'
                          : serverOnline == true
                          ? 'MiomiPay terhubung'
                          : 'Mode offline (simulasi lokal)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: serverOnline == true
                            ? PosColors.success
                            : PosColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Card QR + tombol salin ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: PosColors.border),
          ),
          child: Column(
            children: [
              // Label judul
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.qr_code_2_rounded,
                    size: 20,
                    color: PosColors.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Scan QRIS untuk membayar',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: PosColors.primary,
                    ),
                  ),
                  if (charge.offlineSimulation) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: PosColors.warningSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'OFFLINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: PosColors.warning,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Gambar QR
              AnimatedBuilder(
                animation: pulseCtrl,
                builder: (context, child) => Transform.scale(
                  scale: 1.0 + pulseCtrl.value * 0.015,
                  child: child,
                ),
                child: QrImageView(
                  data: charge.qrString,
                  size: 220,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: PosColors.primaryDark,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: PosColors.primaryDark,
                  ),
                  embeddedImage: null,
                ),
              ),
              const SizedBox(height: 16),

              // Timer menunggu
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: PosColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Menunggu $_elapsed',
                    style: const TextStyle(
                      color: PosColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              // Box link simulasi — selalu tampil jika bukan mode offline
              if (!charge.offlineSimulation) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _CopyLinkRow(
                  charge: charge,
                  linkCopied: linkCopied,
                  onCopyQrLink: onCopyQrLink,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Banner setelah link disalin ───────────────────────────────────
        if (linkCopied) ...[
          _LinkCopiedBanner(elapsedSeconds: elapsedSeconds),
          const SizedBox(height: 16),
        ],

        // ── Langkah panduan ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F6F2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              _InfoStep(
                step: '1',
                text: 'Scan QR di atas, ATAU salin link simulasi dan paste di halaman MiomiPay',
              ),
              _InfoStep(
                step: '2',
                text: 'MiomiPay memproses pembayaran setelah link di-paste',
              ),
              _InfoStep(
                step: '3',
                text: 'Struk muncul otomatis setelah pembayaran diterima',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Tombol batal ──────────────────────────────────────────────────
        OutlinedButton.icon(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: PosColors.danger,
            side: const BorderSide(color: PosColors.dangerSoft),
            minimumSize: const Size(0, 48),
          ),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Batalkan Pesanan'),
        ),
      ],
    );
  }
}

// ── Box link simulasi (di dalam card QR) ─────────────────────────────────────

class _CopyLinkRow extends StatelessWidget {
  const _CopyLinkRow({
    required this.charge,
    required this.linkCopied,
    required this.onCopyQrLink,
  });

  final MiomiPayCharge charge;
  final bool linkCopied;
  final VoidCallback onCopyQrLink;

  /// Nilai yang akan disalin — prioritas checkout_url → qr_image_url →
  /// snap_token → reference. Semua format diterima MiomiPay untuk simulasi.
  String get _link =>
      charge.checkoutUrl ??
      charge.qrImageUrl ??
      charge.snapToken ??
      charge.reference;

  /// Label jenis nilai yang ditampilkan.
  String get _linkLabel {
    if (charge.checkoutUrl != null) return 'Checkout URL';
    if (charge.qrImageUrl != null) return 'QR Image URL';
    if (charge.snapToken != null) return 'Snap Token';
    return 'Reference';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Icon(
              linkCopied ? Icons.check_circle_rounded : Icons.content_paste_rounded,
              size: 14,
              color: linkCopied ? PosColors.success : PosColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              linkCopied
                  ? 'Link simulasi sudah disalin'
                  : 'Link simulasi MiomiPay ($_linkLabel)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: linkCopied ? PosColors.success : PosColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Box link + tombol salin
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: linkCopied
                        ? PosColors.success.withAlpha(120)
                        : PosColors.border,
                  ),
                ),
                child: Text(
                  _link,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: PosColors.text,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: onCopyQrLink,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      linkCopied ? PosColors.success : PosColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  linkCopied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 15,
                ),
                label: Text(
                  linkCopied ? 'Tersalin' : 'Salin',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          linkCopied
              ? 'Paste link di halaman simulasi MiomiPay untuk menyelesaikan pembayaran.'
              : 'Salin lalu paste di halaman simulasi MiomiPay.',
          style: TextStyle(
            fontSize: 11,
            color: linkCopied
                ? PosColors.success.withAlpha(180)
                : PosColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Banner setelah link disalin ───────────────────────────────────────────────

class _LinkCopiedBanner extends StatelessWidget {
  const _LinkCopiedBanner({required this.elapsedSeconds});
  final int elapsedSeconds;

  String get _elapsed {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosColors.primary.withAlpha(60)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: PosColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Menunggu pembayaran di MiomiPay…',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: PosColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Struk otomatis muncul setelah transaksi diterima. ($_elapsed)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: PosColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info step ─────────────────────────────────────────────────────────────────

class _InfoStep extends StatelessWidget {
  const _InfoStep({required this.step, required this.text});
  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: PosColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: PosColors.text),
            ),
          ),
        ],
      ),
    );
  }
}
