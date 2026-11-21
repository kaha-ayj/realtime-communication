import 'dart:async';

import 'package:flutter/material.dart';
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
  bool _simulating = false;
  bool? _serverOnline; // null = belum dicek
  Timer? _pollTimer;
  int _elapsedSeconds = 0;
  Timer? _clockTimer;

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

  /// Cek apakah API/mock server MiomiPay dapat dihubungi.
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
    if (_charge!.offlineSimulation) return; // offline mode pakai tombol manual
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

  Future<void> _simulatePayment() async {
    if (_charge == null || _simulating) return;
    setState(() => _simulating = true);

    try {
      final provider = context.read<AppProvider>();
      final status = _charge!.offlineSimulation
          ? MiomiPayStatus.paid
          : await provider.miomiPayService.simulatePayment(
              _charge!.reference,
              snapToken: _charge!.snapToken,
            );

      if (!mounted) return;
      setState(() => _charge = _charge!.copyWith(status: status));
      if (_charge!.isPaid) _onPaymentSuccess();
    } catch (e) {
      if (!mounted) return;
      if (Config.miomiPaySandbox) {
        // Sandbox: jangan blokir demo bila endpoint simulasi bermasalah.
        setState(
          () => _charge = _charge!.copyWith(status: MiomiPayStatus.paid),
        );
        _onPaymentSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memproses pembayaran: $e'),
            backgroundColor: PosColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  Future<void> _onPaymentSuccess() async {
    _pollTimer?.cancel();
    _clockTimer?.cancel();

    final provider = context.read<AppProvider>();
    // Pembayaran dianggap simulasi bila server offline ATAU gateway masih sandbox.
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
      // Kabari MiomiPay agar tagihan tidak menggantung.
      if (_charge != null && !_charge!.offlineSimulation) {
        await provider.miomiPayService.cancelCharge(_charge!.reference);
      }
      if (mounted) nav.pop();
    }
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
              sandboxMode: Config.miomiPaySandbox,
              simulating: _simulating,
              serverOnline: _serverOnline,
              pulseCtrl: _pulseCtrl,
              onSimulate: _simulatePayment,
              onCancel: _cancelOrder,
            ),
    );
  }
}

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
            PosButton(label: 'Coba Lagi', icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _PaidView extends StatelessWidget {
  const _PaidView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 80,
            color: PosColors.success,
          ),
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
              expired
                  ? Icons.timer_off_outlined
                  : Icons.error_outline_rounded,
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
              style: const TextStyle(
                color: PosColors.textMuted,
                fontSize: 13.5,
              ),
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

class _QrisView extends StatelessWidget {
  const _QrisView({
    required this.charge,
    required this.order,
    required this.elapsedSeconds,
    required this.sandboxMode,
    required this.simulating,
    required this.serverOnline,
    required this.pulseCtrl,
    required this.onSimulate,
    required this.onCancel,
  });

  final MiomiPayCharge charge;
  final PosOrder order;
  final int elapsedSeconds;
  final bool sandboxMode;
  final bool simulating;
  final bool? serverOnline;
  final AnimationController pulseCtrl;
  final VoidCallback onSimulate;
  final VoidCallback onCancel;

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
        // Header nominal
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
                style: const TextStyle(
                  fontSize: 12,
                  color: PosColors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              // Status koneksi ke API MiomiPay
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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

        // QR Code
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: PosColors.border),
          ),
          child: Column(
            children: [
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
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Info
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
                text: 'Buka aplikasi e-wallet atau mobile banking Anda',
              ),
              _InfoStep(step: '2', text: 'Pilih menu Scan QR / QRIS'),
              _InfoStep(step: '3', text: 'Arahkan kamera ke kode QR di atas'),
              _InfoStep(
                step: '4',
                text: 'Konfirmasi nominal dan selesaikan pembayaran',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Sandbox / simulasi
        if (sandboxMode)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PosColors.warningSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PosColors.warning.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.science_rounded,
                      size: 16,
                      color: PosColors.warning,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Mode Sandbox / Simulasi',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: PosColors.warning,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  Config.miomiPayMissingApiKey
                      ? 'API key MiomiPay belum diisi, jadi aplikasi memakai simulasi lokal. '
                            'Jalankan dengan --dart-define-from-file=dart_defines.sandbox.json.'
                      : 'Transaksi memakai lingkungan sandbox MiomiPay. '
                            'Gunakan tombol di bawah untuk mensimulasikan pembayaran berhasil.',
                  style: const TextStyle(fontSize: 12, color: PosColors.warning),
                ),
                if (charge.invoiceReference != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Invoice: ${charge.invoiceReference}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosColors.warning,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: simulating ? null : onSimulate,
                    style: FilledButton.styleFrom(
                      backgroundColor: PosColors.warning,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                    icon: simulating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.flash_on_rounded, size: 18),
                    label: Text(
                      simulating ? 'Memproses…' : 'Simulasi Pembayaran Berhasil',
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

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
