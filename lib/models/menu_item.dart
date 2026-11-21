import 'package:cloud_firestore/cloud_firestore.dart';

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.description,
    required this.emoji,
    required this.isAvailable,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String category;
  final int price;
  final String description;
  final String emoji;
  final bool isAvailable;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MenuItem copyWith({
    String? name,
    String? category,
    int? price,
    String? description,
    String? emoji,
    bool? isAvailable,
  }) {
    return MenuItem(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      description: description ?? this.description,
      emoji: emoji ?? this.emoji,
      isAvailable: isAvailable ?? this.isAvailable,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'category': category.trim(),
      'price': price,
      'description': description.trim(),
      'emoji': emoji,
      'isAvailable': isAvailable,
    };
  }

  factory MenuItem.fromMap(String id, Map<String, dynamic> map) {
    return MenuItem(
      id: id,
      name: (map['name'] as String?) ?? 'Tanpa nama',
      category: (map['category'] as String?) ?? 'Lainnya',
      price: _toInt(map['price']),
      description: (map['description'] as String?) ?? '',
      emoji: (map['emoji'] as String?)?.isNotEmpty == true
          ? map['emoji'] as String
          : '🍽️',
      isAvailable: (map['isAvailable'] as bool?) ?? true,
      createdAt: _toDate(map['createdAt']),
      updatedAt: _toDate(map['updatedAt']),
    );
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
