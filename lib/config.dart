import 'package:flutter/foundation.dart';

/// Konfigurasi global aplikasi.
///
/// Nilai yang dapat diubah saat build:
/// `flutter run --dart-define=MIOMIPAY_BASE_URL=http://192.168.1.10:4000`
class Config {
  Config._();

  // ---------------------------------------------------------------------------
  // Firebase
  // ---------------------------------------------------------------------------
  /// Nama database Firestore yang dipakai aplikasi.
  ///
  /// Firebase project ini memakai database bernama `default` (bukan `(default)`)
  /// agar tetap berjalan pada kuota Spark.
  static const String firestoreDatabaseId = String.fromEnvironment(
    'FIRESTORE_DATABASE_ID',
    defaultValue: 'default',
  );

  // ---------------------------------------------------------------------------
  // MiomiPay
  // ---------------------------------------------------------------------------
  /// Base URL API MiomiPay. Secara default mengarah ke mock server lokal
  /// (`server/miomipay-mock.js`) supaya alur pembayaran bisa didemokan.
  static const String _miomiPayBaseUrlOverride = String.fromEnvironment(
    'MIOMIPAY_BASE_URL',
  );

  static const String miomiPayApiKey = String.fromEnvironment(
    'MIOMIPAY_API_KEY',
    defaultValue: 'miomipay_sandbox_key',
  );

  static const String miomiPayMerchantId = String.fromEnvironment(
    'MIOMIPAY_MERCHANT_ID',
    defaultValue: 'POS-DEMO-001',
  );

  /// `true` menampilkan tombol simulasi pembayaran di layar QRIS.
  static const bool miomiPaySandbox = bool.fromEnvironment(
    'MIOMIPAY_SANDBOX',
    defaultValue: true,
  );

  static String get miomiPayBaseUrl {
    if (_miomiPayBaseUrlOverride.isNotEmpty) {
      return _miomiPayBaseUrlOverride;
    }
    return 'http://$_host:4000';
  }

  // ---------------------------------------------------------------------------
  // Server demo realtime (opsional, dari modul sebelumnya)
  // ---------------------------------------------------------------------------
  static const int port = 3000;
  static const int grpcPort = 50051;

  static String get _host {
    if (kIsWeb) return 'localhost';
    if (defaultTargetPlatform == TargetPlatform.android) return '10.0.2.2';
    return 'localhost';
  }

  static String get baseUrl => 'http://$_host:$port';
  static String get wsUrl => 'ws://$_host:$port';

  static String get dataUrl => '$baseUrl/api/data';
  static String get historyUrl => '$baseUrl/api/history';
  static String get messageUrl => '$baseUrl/api/message';
  static String get longPollUrl => '$baseUrl/api/long-poll';
  static String get eventsUrl => '$baseUrl/api/events';
  static String get sseUrl => eventsUrl;

  static String get grpcHost => _host;
}
