import 'menu_item.dart';

class CartItem {
  const CartItem({required this.menu, required this.quantity});

  final MenuItem menu;
  final int quantity;

  int get subtotal => menu.price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(menu: menu, quantity: quantity ?? this.quantity);
  }
}
