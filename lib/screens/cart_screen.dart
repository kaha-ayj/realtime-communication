import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../providers/app_provider.dart';
import '../services/order.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';
import '../widgets/menu_photo.dart';
import 'payment_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final items = provider.cartItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keranjang'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, provider),
              child: const Text(
                'Kosongkan',
                style: TextStyle(color: PosColors.danger, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Keranjang kosong',
              subtitle: 'Tambahkan menu dari halaman kasir.',
              action: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Kembali ke Menu'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: items.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _CartItemCard(
                item: items[i],
                provider: provider,
              ),
            ),
      bottomNavigationBar: items.isEmpty
          ? null
          : _CheckoutBar(items: items, total: provider.cartTotal),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kosongkan Keranjang?'),
        content: const Text(
          'Semua item dalam keranjang akan dihapus.',
        ),
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
            child: const Text('Kosongkan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      provider.clearCart();
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({required this.item, required this.provider});
  final CartItem item;
  final AppProvider provider;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Foto produk
            MenuPhoto(
              menu: item.menu,
              width: 56,
              height: 56,
              borderRadius: 14,
              emojiSize: 26,
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.menu.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatCurrency(item.menu.price),
                    style: const TextStyle(
                      color: PosColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Subtotal: ${formatCurrency(item.subtotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: PosColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Quantity controls
            Column(
              children: [
                Row(
                  children: [
                    _QtyBtn(
                      icon: Icons.remove_rounded,
                      onTap: () => provider.removeFromCart(item.menu.id),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _QtyBtn(
                      icon: Icons.add_rounded,
                      onTap: () => provider.addToCart(item.menu),
                      primary: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => provider.deleteFromCart(item.menu.id),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: PosColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: primary ? PosColors.primary : PosColors.primarySoft,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: primary ? Colors.white : PosColors.primary,
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatefulWidget {
  const _CheckoutBar({required this.items, required this.total});
  final List<CartItem> items;
  final int total;

  @override
  State<_CheckoutBar> createState() => _CheckoutBarState();
}

class _CheckoutBarState extends State<_CheckoutBar> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ringkasan
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.items.length} item',
                  style: const TextStyle(
                    color: PosColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                Row(
                  children: [
                    const Text(
                      'Total  ',
                      style: TextStyle(
                        color: PosColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      formatCurrency(widget.total),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: PosColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            PosButton(
              label: 'Proses Pembayaran',
              icon: Icons.payment_rounded,
              loading: _loading,
              onPressed: () => _checkout(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkout(BuildContext context) async {
    final provider = context.read<AppProvider>();
    final user = provider.currentUser;
    if (user == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _loading = true);

    try {
      // Buat pesanan pending di Firestore
      final orderItems = widget.items
          .map(
            (ci) => OrderItem(
              menuId: ci.menu.id,
              name: ci.menu.name,
              price: ci.menu.price,
              quantity: ci.quantity,
              emoji: ci.menu.emoji,
              imageUrl: ci.menu.imageUrl,
            ),
          )
          .toList();

      final code = OrderService.generateCode();
      final order = await provider.orderService.createPendingOrder(
        cashier: user,
        items: orderItems,
        total: widget.total,
        code: code,
      );

      if (!mounted) return;

      // Navigasi ke layar pembayaran
      await navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentScreen(order: order),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal membuat pesanan: $e'),
          backgroundColor: PosColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
