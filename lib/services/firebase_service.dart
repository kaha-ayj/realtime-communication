import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../config.dart';

/// Akses Firestore memakai database bernama sesuai konfigurasi project.
FirebaseFirestore createFirestore() {
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: Config.firestoreDatabaseId,
  );
}
