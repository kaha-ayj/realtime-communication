import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../providers/app_provider.dart';
import '../services/order.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';
import '../widgets/menu_photo.dart';
import 'receipt_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.adminMode});
  final bool adminMode;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _filter = 'Semua'; // Semua | pending | paid | cancelled

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final currentUser = provider.currentUser;

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Semua', 'pending', 'paid', 'cancelled']
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: CategoryChip(
                        label: _filterLabel(f),
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: StreamBuilder<List<PosOrder>>(
            stream: provider.orderService.watchOrders(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Gagal memuat pesanan:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: PosColors.textMuted),
                  ),
                );
              }

              var orders = snapshot.data ?? [];

              // Kasir hanya lihat pesanannya sendiri
              if (!widget.adminMode && currentUser != null) {
                orders = orders
                    .where((o) => o.cashierId == currentUser.uid)
                    .toList();
              }

              // Filter status
              if (_filter != 'Semua') {
                orders = orders.where((o) => o.status.name == _filter).toList();
              }

              if (orders.isEmpty) {
                return EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: _filter == 'Semua'
                      ? 'Belum ada pesanan'
                      : 'Tidak ada pesanan ${_filterLabel(_filter).toLowerCase()}',
                  subtitle: _filter == 'Semua'
                      ? widget.adminMode
                            ? 'Pesanan dari kasir akan muncul di sini.'
                            : 'Pesanan Anda akan muncul di sini.'
                      : null,
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: orders.length,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _OrderCard(
                  order: orders[i],
                  adminMode: widget.adminMode,
                  orderService: provider.orderService,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _filterLabel(String f) => switch (f) {
    'pending' => 'Menunggu',
    'paid' => 'Lunas',
    'cancelled' => 'Dibatalkan',
    _ => 'Semua',
  };
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.adminMode,
    required this.orderService,
  });

  final PosOrder order;
  final bool adminMode;
  final OrderService orderService;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.code,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(order.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: PosColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OrderStatusChip(status: order.status.name),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Items preview
              Text(
                order.items.map((i) => '${i.emoji} ${i.name} ×${i.quantity}').join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PosColors.textMuted,
                  fontSize: 12.5,
                ),
              ),

              const SizedBox(height: 10),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (adminMode)
                        Row(
                          children: [
                            const Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: PosColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              order.cashierName,
                              style: const TextStyle(
                                fontSize: 12,
                                color: PosColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      const Icon(
                        Icons.shopping_bag_outlined,
                        size: 14,
                        color: PosColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${order.itemCount} item',
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    formatCurrency(order.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: PosColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    if (order.status == OrderStatus.paid) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)),
      );
    } else {
      _showOrderDetail(context);
    }
  }

  void _showOrderDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: PosColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.code,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                OrderStatusChip(status: order.status.name),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(order.createdAt),
              style: const TextStyle(color: PosColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),

            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    ProductPhoto(
                      name: item.name,
                      imageUrl: item.imageUrl,
                      emoji: item.emoji,
                      width: 34,
                      height: 34,
                      borderRadius: 10,
                      emojiSize: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${item.name} ×${item.quantity}',
                        style: const TextStyle(fontSize: 13.5),
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
            const Divider(height: 24),
            InfoRow(
              label: 'Total',
              value: formatCurrency(order.total),
              bold: true,
              valueColor: PosColors.primary,
            ),
            const SizedBox(height: 8),
            InfoRow(label: 'Kasir', value: order.cashierName),
            const SizedBox(height: 8),
            InfoRow(label: 'Metode', value: order.paymentMethod),

            if (adminMode && order.status == OrderStatus.pending) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  await orderService.markCancelled(order.id);
                  if (context.mounted) Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: PosColors.danger,
                  minimumSize: const Size(double.infinity, 48),
                ),
                icon: const Icon(Icons.cancel_rounded),
                label: const Text('Batalkan Pesanan'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
