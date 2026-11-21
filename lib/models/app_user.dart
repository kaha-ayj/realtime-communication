enum UserRole {
  admin,
  kasir;

  String get label => switch (this) {
    UserRole.admin => 'Admin',
    UserRole.kasir => 'Kasir',
  };

  String get description => switch (this) {
    UserRole.admin => 'Kelola menu & pantau penjualan',
    UserRole.kasir => 'Layani pesanan & pembayaran',
  };

  static UserRole? fromString(String? value) {
    return switch (value) {
      'admin' => UserRole.admin,
      'kasir' => UserRole.kasir,
      _ => null,
    };
  }
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final DateTime? createdAt;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return email.isNotEmpty ? email[0].toUpperCase() : '?';
    }
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    final rawCreated = map['createdAt'];
    return AppUser(
      uid: uid,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? map['name'] as String
          : 'Pengguna POS',
      email: (map['email'] as String?) ?? '',
      role: UserRole.fromString(map['role'] as String?) ?? UserRole.kasir,
      createdAt: rawCreated is DateTime
          ? rawCreated
          : rawCreated is String
          ? DateTime.tryParse(rawCreated)
          : null,
    );
  }
}
