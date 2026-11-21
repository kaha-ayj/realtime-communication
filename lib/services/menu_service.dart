import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/sample_menus.dart';
import '../models/menu_item.dart';
import 'firebase_service.dart';

class MenuService {
  MenuService({FirebaseFirestore? firestore})
    : _db = firestore ?? createFirestore();

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _menus =>
      _db.collection('menus');

  Stream<List<MenuItem>> watchMenus() {
    return _menus.orderBy('name').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => MenuItem.fromMap(doc.id, doc.data()))
          .toList(),
    );
  }

  Future<void> addMenu(MenuItem menu) {
    return _menus.add({
      ...menu.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMenu(MenuItem menu) {
    return _menus.doc(menu.id).update({
      ...menu.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMenu(String menuId) => _menus.doc(menuId).delete();

  Future<void> setAvailability(String menuId, bool isAvailable) {
    return _menus.doc(menuId).update({
      'isAvailable': isAvailable,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> seedSampleMenus() async {
    final batch = _db.batch();
    for (final menu in sampleMenus) {
      final ref = _menus.doc();
      batch.set(ref, {
        ...menu.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
