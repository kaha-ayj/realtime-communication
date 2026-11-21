import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../models/order.dart';
import 'firebase_service.dart';

class AuthProfileException implements Exception {
  const AuthProfileException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = firestore ?? createFirestore();

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  User? get currentFirebaseUser => _auth.currentUser;

  Stream<AppUser?> watchCurrentUser() async* {
    await for (final firebaseUser in _auth.authStateChanges()) {
      if (firebaseUser == null) {
        yield null;
        continue;
      }

      final profile = await _loadProfile(firebaseUser.uid);
      if (profile == null) {
        await _auth.signOut();
        yield null;
      } else {
        yield profile;
      }
    }
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw const AuthProfileException('Login gagal. Silakan coba lagi.');
    }

    final profile = await _loadProfile(user.uid);
    if (profile == null) {
      await _auth.signOut();
      throw const AuthProfileException(
        'Akun ini belum terdaftar sebagai pengguna POS. '
        'Hubungi admin untuk mengatur role akun Anda.',
      );
    }

    return profile;
  }

  Future<void> signOut() => _auth.signOut();

  Future<AppUser?> _loadProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;

    final data = doc.data() ?? <String, dynamic>{};
    if (UserRole.fromString(data['role'] as String?) == null) return null;
    return AppUser.fromMap(uid, data);
  }

  static String readableError(Object error) {
    if (error is AuthProfileException) return error.message;

    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => 'Format email tidak valid.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => 'Email atau password salah.',
        'user-disabled' => 'Akun ini telah dinonaktifkan.',
        'too-many-requests' =>
          'Terlalu banyak percobaan login. Coba lagi beberapa saat lagi.',
        'network-request-failed' =>
          'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
        'operation-not-allowed' =>
          'Login email/password belum diaktifkan pada project Firebase.',
        'configuration-not-found' =>
          'Firebase Authentication belum dikonfigurasi dengan benar.',
        _ => 'Login gagal (${error.code}). Silakan coba lagi.',
      };
    }

    return 'Terjadi kesalahan: $error';
  }
}

class OrderService {
  OrderService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? createFirestore(),
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Stream<List<PosOrder>> watchOrders({int limit = 300}) {
    return _db
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PosOrder.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<PosOrder> createPendingOrder({
    required AppUser cashier,
    required List<OrderItem> items,
    required int total,
    required String code,
    String note = '',
  }) async {
    final ref = _db.collection('orders').doc();
    final order = PosOrder(
      id: ref.id,
      code: code,
      cashierId: cashier.uid,
      cashierName: cashier.name,
      items: items,
      total: total,
      status: OrderStatus.pending,
      note: note,
      createdAt: DateTime.now(),
    );

    final data = order.toMap();
    data['cashierId'] = cashier.uid;
    data['status'] = OrderStatus.pending.name;

    await ref.set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'paidAt': null,
    });
    return order;
  }

  Future<void> attachPayment({
    required String orderId,
    required String reference,
    required bool isSimulated,
  }) {
    return _db.collection('orders').doc(orderId).update({
      'paymentReference': reference,
      'isSimulatedPayment': isSimulated,
      'paymentMethod': 'QRIS · MiomiPay',
    });
  }

  Future<void> markPaid({
    required String orderId,
    String? reference,
    bool? isSimulated,
  }) {
    return _db.collection('orders').doc(orderId).update({
      'status': OrderStatus.paid.name,
      'paidAt': FieldValue.serverTimestamp(),
      'paymentReference': ?reference,
      'isSimulatedPayment': ?isSimulated,
    });
  }

  Future<void> markCancelled(String orderId) {
    return _db.collection('orders').doc(orderId).update({
      'status': OrderStatus.cancelled.name,
    });
  }

  bool get isSignedIn => _auth.currentUser != null;

  static String generateCode() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final millis = now.millisecond.toString().padLeft(3, '0');
    return 'POS${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}$millis';
  }
}
