import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/order.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.order});
  final PosOrder order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosColors.background,
      appBar: AppBar(
        title: const Text('Struk Pembayaran'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          children: [
            // Success icon
            Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: PosColors.successSoft,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: PosColors.success.withAlpha(60),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 50,
                      color: PosColors.success,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Pembayaran Berhasil!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: PosColors.success,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.isSimulatedPayment
                        ? 'Simulasi · MiomiPay Sandbox'
                        : 'QRIS · MiomiPay',
                    style: const TextStyle(
                      color: PosColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Struk card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: PosColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header struk
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: PosColors.primarySoft,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.point_of_sale_rounded,
                          color: PosColors.primary,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'POS Sederhana',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: PosColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kode: ${order.code}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: PosColors.textMuted,
                          ),
                        ),
                        if (order.paidAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _formatDateTime(order.paidAt!),
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Items
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Item list
                        ...order.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Text(
                                  item.emoji,
                                  style: const TextStyle(fontSize: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      Text(
                                        '${formatCurrency(item.price)} × ${item.quantity}',
                                        style: const TextStyle(
                                          color: PosColors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatCurrency(item.subtotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1),
                        ),

                        // Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              formatCurrency(order.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                color: PosColors.primary,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),

                        // Info tambahan
                        InfoRow(
                          label: 'Kasir',
                          value: order.cashierName,
                        ),
                        const SizedBox(height: 6),
                        InfoRow(
                          label: 'Metode Bayar',
                          value: order.paymentMethod,
                        ),
                        if (order.paymentReference != null) ...[
                          const SizedBox(height: 6),
                          InfoRow(
                            label: 'Ref. Pembayaran',
                            value: order.paymentReference!.length > 20
                                ? '${order.paymentReference!.substring(0, 20)}…'
                                : order.paymentReference!,
                          ),
                        ],
                        if (order.isSimulatedPayment) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: PosColors.warningSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '⚠️  Ini adalah pembayaran simulasi untuk keperluan demo.',
                              style: TextStyle(
                                fontSize: 11,
                                color: PosColors.warning,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Footer struk
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      color: PosColors.primarySoft,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Terima kasih atas pesanan Anda!',
                          style: TextStyle(
                            color: PosColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Powered by Firebase & MiomiPay',
                          style: TextStyle(
                            color: PosColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Tombol kembali
            PosButton(
              label: 'Transaksi Baru',
              icon: Icons.add_shopping_cart_rounded,
              onPressed: () {
                // Kembali ke root (CashierShell)
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
