import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/menu_item.dart';
import '../providers/app_provider.dart';
import '../services/order.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';
import '../widgets/menu_photo.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';

class CashierShell extends StatefulWidget {
  const CashierShell({super.key});

  @override
  State<CashierShell> createState() => _CashierShellState();
}

class _CashierShellState extends State<CashierShell> {
  int _selectedIndex = 0;

  static const _pages = [
    _CashierPage(),
    OrdersScreen(adminMode: false),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser!;
    final cartCount = provider.cartItemCount;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(initials: user.initials),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: PosColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Kasir',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: PosColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_selectedIndex == 0)
            CartBadge(
              count: cartCount,
              child: IconButton(
                onPressed: cartCount > 0
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CartScreen()),
                        )
                    : null,
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'Keranjang',
              ),
            ),
          IconButton(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Keluar',
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'Menu',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Riwayat',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Keluar'),
        content: const Text('Yakin ingin keluar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PosColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<AppProvider>().clearCart();
      await context.read<AppProvider>().signOut();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Halaman utama kasir
// ─────────────────────────────────────────────────────────────────────────────

class _CashierPage extends StatefulWidget {
  const _CashierPage();

  @override
  State<_CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<_CashierPage> {
  String _search = '';
  String _selectedCategory = 'Semua';

  @override
  Widget build(BuildContext context) {
    final menuService = context.read<AppProvider>().menuService;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Cari menu…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: StreamBuilder<List<MenuItem>>(
            stream: menuService.watchMenus(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allMenus = (snapshot.data ?? [])
                  .where((m) => m.isAvailable)
                  .toList();

              final categories = <String>{'Semua'};
              for (final m in allMenus) {
                categories.add(m.category);
              }
              final sortedCats = [
                'Semua',
                ...categories.where((c) => c != 'Semua').toList()..sort(),
              ];

              final filtered = allMenus.where((m) {
                final matchSearch = _search.isEmpty ||
                    m.name.toLowerCase().contains(_search) ||
                    m.category.toLowerCase().contains(_search);
                final matchCat = _selectedCategory == 'Semua' ||
                    m.category == _selectedCategory;
                return matchSearch && matchCat;
              }).toList();

              if (allMenus.isEmpty) {
                return const EmptyState(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Belum ada menu tersedia',
                  subtitle: 'Admin belum menambahkan menu. Hubungi admin.',
                );
              }

              return Column(
                children: [
                  // Category chips
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: sortedCats.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => CategoryChip(
                        label: sortedCats[i],
                        selected: _selectedCategory == sortedCats[i],
                        onTap: () =>
                            setState(() => _selectedCategory = sortedCats[i]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child: filtered.isEmpty
                        ? const EmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'Menu tidak ditemukan',
                            subtitle: 'Coba ubah kata kunci pencarian.',
                          )
                        : _MenuGrid(menus: filtered),
                  ),
                ],
              );
            },
          ),
        ),

        // Cart summary bar
        const _CartBar(),
      ],
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.menus});
  final List<MenuItem> menus;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 0.66,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: menus.length,
      itemBuilder: (context, i) => _MenuCard(menu: menus[i]),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.menu});
  final MenuItem menu;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final qty = provider.quantityOf(menu.id);

    return GestureDetector(
      onTap: () => provider.addToCart(menu),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: qty > 0 ? PosColors.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: qty > 0 ? PosColors.primary : PosColors.border,
            width: qty > 0 ? 1.6 : 1,
          ),
          boxShadow: qty > 0
              ? [
                  BoxShadow(
                    color: PosColors.primary.withAlpha(30),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Foto produk + qty badge
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1.5,
                    child: MenuPhoto(
                      menu: menu,
                      width: double.infinity,
                      borderRadius: 14,
                      emojiSize: 34,
                    ),
                  ),
                  if (qty > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: PosColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(25),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Text(
                          '$qty',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                menu.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: PosColors.text,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                menu.category,
                style: const TextStyle(
                  fontSize: 11,
                  color: PosColors.textMuted,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      formatCurrency(menu.price),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color:
                            qty > 0 ? PosColors.primaryDark : PosColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: qty > 0 ? PosColors.primary : PosColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      qty > 0 ? Icons.add_rounded : Icons.add_rounded,
                      color: qty > 0 ? Colors.white : PosColors.primary,
                      size: 18,
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
}

class _CartBar extends StatelessWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final count = provider.cartItemCount;
    final total = provider.cartTotal;

    if (count == 0) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SafeArea(
        child: FilledButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CartScreen()),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 54),
            backgroundColor: PosColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count item',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Lihat Keranjang',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                formatCurrency(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
