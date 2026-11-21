import 'package:flutter/foundation.dart';

/// Konfigurasi global aplikasi.
///
/// Nilai dapat diubah saat build:
/// `flutter run --dart-define-from-file=dart_defines.sandbox.json`
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
  /// Base URL API MiomiPay.
  ///
  /// Default mengarah ke gateway asli MiomiPay. Untuk memakai mock server lokal:
  /// `--dart-define=MIOMIPAY_BASE_URL=http://localhost:4000/api/v1`
  static const String _miomiPayBaseUrlOverride = String.fromEnvironment(
    'MIOMIPAY_BASE_URL',
    defaultValue: 'https://pg.miomidev.com/api/v1',
  );

  /// API key MiomiPay.
  ///
  /// **Jangan** menaruh nilai asli di berkas ini. Isi lewat
  /// `--dart-define` atau `--dart-define-from-file`.
  ///
  /// - Sandbox: kunci berawalan `MP-SB-`
  /// - Live   : kunci berawalan `MP-LIVE-`
  static const String miomiPayApiKey = String.fromEnvironment(
    'MIOMIPAY_API_KEY',
  );

  /// ID merchant (opsional, hanya untuk metadata/log).
  static const String miomiPayMerchantId = String.fromEnvironment(
    'MIOMIPAY_MERCHANT_ID',
    defaultValue: 'POS-DEMO-001',
  );

  /// URL callback/webhook yang dikirim saat membuat tagihan.
  static const String miomiPayCallbackUrl = String.fromEnvironment(
    'MIOMIPAY_CALLBACK_URL',
  );

  /// `true` mengaktifkan tombol simulasi pembayaran di layar QRIS.
  ///
  /// Gunakan `false` untuk transaksi uang nyata.
  static const bool miomiPaySandbox = bool.fromEnvironment(
    'MIOMIPAY_SANDBOX',
    defaultValue: true,
  );

  static String get miomiPayBaseUrl {
    final value = _miomiPayBaseUrlOverride;
    return value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
  }

  /// True bila API key belum diisi.
  static bool get miomiPayMissingApiKey => miomiPayApiKey.trim().isEmpty;

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
