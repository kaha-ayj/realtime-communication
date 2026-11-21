import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/menu_item.dart';
import '../providers/app_provider.dart';
import '../services/order.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';
import 'dashboard_screen.dart';
import 'menu_form_screen.dart';
import 'orders_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  static const _pages = [
    DashboardScreen(),
    _MenuManagementPage(),
    OrdersScreen(adminMode: true),
  ];

  @override
  Widget build(BuildContext context) {
    final user = context.read<AppProvider>().currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(initials: user.initials, admin: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: PosColors.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: PosColors.warning,
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
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu_rounded),
            label: 'Kelola Menu',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Riwayat Pesanan',
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
        content: const Text('Yakin ingin keluar dari akun admin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PosColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppProvider>().signOut();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Halaman kelola menu
// ─────────────────────────────────────────────────────────────────────────────

class _MenuManagementPage extends StatefulWidget {
  const _MenuManagementPage();

  @override
  State<_MenuManagementPage> createState() => _MenuManagementPageState();
}

class _MenuManagementPageState extends State<_MenuManagementPage> {
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Cari menu…',
                    prefixIcon: Icon(Icons.search_rounded),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MenuFormScreen()),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Tambah'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // StreamBuilder for menu list
        Expanded(
          child: StreamBuilder<List<MenuItem>>(
            stream: menuService.watchMenus(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 56,
                          color: PosColors.border,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Gagal memuat menu\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: PosColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allMenus = snapshot.data ?? [];

              // Ambil kategori unik
              final categories = <String>{'Semua'};
              for (final m in allMenus) {
                categories.add(m.category);
              }
              final sortedCats = ['Semua', ...categories.where((c) => c != 'Semua').toList()..sort()];

              // Filter
              final filtered = allMenus.where((m) {
                final matchSearch = _search.isEmpty ||
                    m.name.toLowerCase().contains(_search) ||
                    m.category.toLowerCase().contains(_search);
                final matchCat = _selectedCategory == 'Semua' ||
                    m.category == _selectedCategory;
                return matchSearch && matchCat;
              }).toList();

              if (allMenus.isEmpty) {
                return EmptyState(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Belum ada menu',
                  subtitle: 'Tambahkan menu pertama untuk mulai berjualan.',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MenuFormScreen()),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah Menu'),
                  ),
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
                        onTap: () => setState(() => _selectedCategory = sortedCats[i]),
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
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: filtered.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _MenuAdminCard(
                              menu: filtered[i],
                              menuService: menuService,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MenuAdminCard extends StatelessWidget {
  const _MenuAdminCard({required this.menu, required this.menuService});

  final MenuItem menu;
  final dynamic menuService;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Emoji
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: PosColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(menu.emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          menu.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!menu.isAvailable)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: PosColors.dangerSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Habis',
                            style: TextStyle(
                              fontSize: 10,
                              color: PosColors.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: PosColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          menu.category,
                          style: const TextStyle(
                            fontSize: 11,
                            color: PosColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatCurrency(menu.price),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: PosColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Column(
              children: [
                _ActionBtn(
                  icon: Icons.edit_outlined,
                  color: PosColors.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MenuFormScreen(menu: menu),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _ActionBtn(
                  icon: menu.isAvailable
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: menu.isAvailable ? PosColors.textMuted : PosColors.success,
                  onTap: () => menuService.setAvailability(
                    menu.id,
                    !menu.isAvailable,
                  ),
                ),
                const SizedBox(height: 6),
                _ActionBtn(
                  icon: Icons.delete_outline_rounded,
                  color: PosColors.danger,
                  onTap: () => _confirmDelete(context, menu, menuService),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    MenuItem menu,
    dynamic menuService,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Menu?'),
        content: Text(
          'Menu "${menu.name}" akan dihapus dan tidak dapat dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PosColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await menuService.deleteMenu(menu.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${menu.name}" berhasil dihapus.')),
        );
      }
    }
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
