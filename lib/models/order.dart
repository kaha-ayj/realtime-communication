import 'package:cloud_firestore/cloud_firestore.dart';

enum OrderStatus {
  pending,
  paid,
  cancelled;

  String get label => switch (this) {
    OrderStatus.pending => 'Menunggu',
    OrderStatus.paid => 'Lunas',
    OrderStatus.cancelled => 'Dibatalkan',
  };

  static OrderStatus fromString(String? value) {
    return switch (value) {
      'paid' => OrderStatus.paid,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.pending,
    };
  }
}

class OrderItem {
  const OrderItem({
    required this.menuId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.emoji,
  });

  final String menuId;
  final String name;
  final int price;
  final int quantity;
  final String emoji;

  int get subtotal => price * quantity;

  Map<String, dynamic> toMap() {
    return {
      'menuId': menuId,
      'name': name,
      'price': price,
      'quantity': quantity,
      'emoji': emoji,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      menuId: (map['menuId'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Item',
      price: _toInt(map['price']),
      quantity: _toInt(map['quantity']),
      emoji: (map['emoji'] as String?) ?? '🍽️',
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class PosOrder {
  const PosOrder({
    required this.id,
    required this.code,
    required this.cashierId,
    required this.cashierName,
    required this.items,
    required this.total,
    required this.status,
    required this.createdAt,
    this.paidAt,
    this.paymentReference,
    this.paymentMethod = 'QRIS · MiomiPay',
    this.note = '',
    this.isSimulatedPayment = false,
  });

  final String id;
  final String code;
  final String cashierId;
  final String cashierName;
  final List<OrderItem> items;
  final int total;
  final OrderStatus status;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final String? paymentReference;
  final String paymentMethod;
  final String note;
  final bool isSimulatedPayment;

  int get itemCount => items.fold(0, (totalCount, item) => totalCount + item.quantity);

  PosOrder copyWith({
    String? id,
    String? code,
    OrderStatus? status,
    DateTime? paidAt,
    String? paymentReference,
    bool? isSimulatedPayment,
  }) {
    return PosOrder(
      id: id ?? this.id,
      code: code ?? this.code,
      cashierId: cashierId,
      cashierName: cashierName,
      items: items,
      total: total,
      status: status ?? this.status,
      createdAt: createdAt,
      paidAt: paidAt ?? this.paidAt,
      paymentReference: paymentReference ?? this.paymentReference,
      paymentMethod: paymentMethod,
      note: note,
      isSimulatedPayment: isSimulatedPayment ?? this.isSimulatedPayment,
    );
  }

  factory PosOrder.fromMap(String id, Map<String, dynamic> map) {
    final rawItems = map['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e)))
              .toList()
        : <OrderItem>[];

    return PosOrder(
      id: id,
      code: (map['code'] as String?) ?? id,
      cashierId: (map['cashierId'] as String?) ?? '',
      cashierName: (map['cashierName'] as String?) ?? 'Kasir',
      items: items,
      total: _toInt(map['total']),
      status: OrderStatus.fromString(map['status'] as String?),
      createdAt: _toDate(map['createdAt']),
      paidAt: _toDate(map['paidAt']),
      paymentReference: map['paymentReference'] as String?,
      paymentMethod: (map['paymentMethod'] as String?) ?? 'QRIS · MiomiPay',
      note: (map['note'] as String?) ?? '',
      isSimulatedPayment: (map['isSimulatedPayment'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'items': items.map((item) => item.toMap()).toList(),
      'total': total,
      'status': status.name,
      'paymentMethod': paymentMethod,
      'paymentReference': paymentReference,
      'note': note,
      'isSimulatedPayment': isSimulatedPayment,
      'createdAt': FieldValue.serverTimestamp(),
      'paidAt': paidAt == null ? null : Timestamp.fromDate(paidAt!),
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
