import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';
import '../services/auth_service.dart';
import '../services/menu_service.dart';
import '../services/miomipay_service.dart';

class AppProvider extends ChangeNotifier {
  AppProvider({
    required AuthService authService,
    required MenuService menuService,
    required OrderService orderService,
    required MiomiPayService miomiPayService,
  })  : _authService = authService,
        _menuService = menuService,
        _orderService = orderService,
        _miomiPayService = miomiPayService;

  final AuthService _authService;
  final MenuService _menuService;
  final OrderService _orderService;
  final MiomiPayService _miomiPayService;

  // ── Auth state ─────────────────────────────────────────────────────────────
  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.role == UserRole.admin;
  bool get isCashier => _currentUser?.role == UserRole.kasir;

  void setCurrentUser(AppUser? user) {
    _currentUser = user;
    if (user == null) _cart.clear();
    notifyListeners();
  }

  Future<void> signOut() => _authService.signOut();

  // ── Cart ───────────────────────────────────────────────────────────────────
  final Map<String, CartItem> _cart = {};
  List<CartItem> get cartItems => _cart.values.toList();
  int get cartItemCount => _cart.values.fold(0, (sum, ci) => sum + ci.quantity);
  int get cartTotal => _cart.values.fold(0, (sum, ci) => sum + ci.subtotal);
  bool get cartIsEmpty => _cart.isEmpty;

  void addToCart(MenuItem menu) {
    final existing = _cart[menu.id];
    if (existing != null) {
      _cart[menu.id] = existing.copyWith(quantity: existing.quantity + 1);
    } else {
      _cart[menu.id] = CartItem(menu: menu, quantity: 1);
    }
    notifyListeners();
  }

  void removeFromCart(String menuId) {
    final existing = _cart[menuId];
    if (existing == null) return;
    if (existing.quantity <= 1) {
      _cart.remove(menuId);
    } else {
      _cart[menuId] = existing.copyWith(quantity: existing.quantity - 1);
    }
    notifyListeners();
  }

  void deleteFromCart(String menuId) {
    _cart.remove(menuId);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  int quantityOf(String menuId) => _cart[menuId]?.quantity ?? 0;

  // ── Services (exposed to screens) ─────────────────────────────────────────
  MenuService get menuService => _menuService;
  OrderService get orderService => _orderService;
  MiomiPayService get miomiPayService => _miomiPayService;
  AuthService get authService => _authService;
}
