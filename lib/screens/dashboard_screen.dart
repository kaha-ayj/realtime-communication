import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../providers/app_provider.dart';
import '../services/order.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';
import '../widgets/menu_photo.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _timeframeIndex = 0; // 0 = Hari Ini, 1 = 7 Hari, 2 = Semua

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();

    return StreamBuilder<List<PosOrder>>(
      stream: provider.orderService.watchOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Gagal memuat analitik:\n${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: PosColors.textMuted),
            ),
          );
        }

        final allOrders = snapshot.data ?? [];
        final now = DateTime.now();

        // Filter based on selected timeframe
        final filteredOrders = allOrders.where((order) {
          if (order.createdAt == null) return true;
          if (_timeframeIndex == 0) {
            // Hari Ini
            return order.createdAt!.year == now.year &&
                order.createdAt!.month == now.month &&
                order.createdAt!.day == now.day;
          } else if (_timeframeIndex == 1) {
            // 7 Hari Terakhir
            final sevenDaysAgo = now.subtract(const Duration(days: 7));
            return order.createdAt!.isAfter(sevenDaysAgo);
          }
          return true; // Semua
        }).toList();

        final paidOrders =
            filteredOrders.where((o) => o.status == OrderStatus.paid).toList();
        final totalRevenue =
            paidOrders.fold<int>(0, (sum, o) => sum + o.total);
        final totalPaidCount = paidOrders.length;
        final avgTicket =
            totalPaidCount > 0 ? (totalRevenue / totalPaidCount).round() : 0;

        // Top selling items
        final itemMap = <String, _ItemStat>{};
        for (final o in paidOrders) {
          for (final it in o.items) {
            final stat = itemMap.putIfAbsent(
              it.name,
              () => _ItemStat(name: it.name, emoji: it.emoji),
            );
            stat.quantity += it.quantity;
            stat.revenue += it.subtotal;
          }
        }
        final topItems = itemMap.values.toList()
          ..sort((a, b) => b.quantity.compareTo(a.quantity));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // Timeframe Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  CategoryChip(
                    label: 'Hari Ini',
                    selected: _timeframeIndex == 0,
                    onTap: () => setState(() => _timeframeIndex = 0),
                  ),
                  const SizedBox(width: 8),
                  CategoryChip(
                    label: '7 Hari Terakhir',
                    selected: _timeframeIndex == 1,
                    onTap: () => setState(() => _timeframeIndex = 1),
                  ),
                  const SizedBox(width: 8),
                  CategoryChip(
                    label: 'Semua Waktu',
                    selected: _timeframeIndex == 2,
                    onTap: () => setState(() => _timeframeIndex = 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Revenue highlight banner card
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [PosColors.primary, PosColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: PosColors.primary.withAlpha(80),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Pendapatan',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$totalPaidCount Transaksi',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    formatCurrency(totalRevenue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.trending_up_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Rata-rata: ${formatCurrency(avgTicket)} / pesanan',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Quick Stats Grid
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Total Pesanan',
                    value: '${filteredOrders.length}',
                    subtitle: '$totalPaidCount Sukses',
                    icon: Icons.receipt_long_rounded,
                    color: PosColors.primary,
                    bgColor: PosColors.primarySoft,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    title: 'Menu Terjual',
                    value: '${topItems.fold<int>(0, (s, i) => s + i.quantity)}',
                    subtitle: '${topItems.length} Variasi menu',
                    icon: Icons.fastfood_rounded,
                    color: PosColors.warning,
                    bgColor: PosColors.accentSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section: Top Selling Items
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Menu Terlaris',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: PosColors.text,
                  ),
                ),
                Text(
                  '${topItems.length} menu',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PosColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (topItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: PosColors.border),
                ),
                child: const Center(
                  child: Text(
                    'Belum ada transaksi pada periode ini',
                    style: TextStyle(color: PosColors.textMuted, fontSize: 13),
                  ),
                ),
              )
            else
              ...topItems.take(5).map((stat) {
                final rank = topItems.indexOf(stat) + 1;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: PosColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: rank == 1
                              ? PosColors.warning
                              : rank == 2
                                  ? const Color(0xFF9E9E9E)
                                  : rank == 3
                                      ? const Color(0xFFCD7F32)
                                      : PosColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$rank',
                            style: TextStyle(
                              color: rank <= 3 ? Colors.white : PosColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ProductPhoto(
                        name: stat.name,
                        emoji: stat.emoji,
                        width: 30,
                        height: 30,
                        borderRadius: 9,
                        emojiSize: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stat.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              '${stat.quantity} porsi terjual',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: PosColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatCurrency(stat.revenue),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: PosColors.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PosColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PosColors.textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: PosColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: PosColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemStat {
  _ItemStat({required this.name, required this.emoji});
  final String name;
  final String emoji;
  int quantity = 0;
  int revenue = 0;
}
