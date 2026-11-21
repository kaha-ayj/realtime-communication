import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/miomipay_charge.dart';

class MiomiPayException implements Exception {
  const MiomiPayException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client API MiomiPay (https://pg.miomidev.com).
///
/// Kontrak yang dipakai:
/// - `POST /transactions` (Bearer API key) → membuat tagihan QRIS.
/// - `GET  /transactions/{snap_token}/status` → status pembayaran.
/// - `POST /sandbox/{snap_token}/simulate-pay` → simulasi lunas (sandbox).
/// - `POST /sandbox/{snap_token}/simulate-expire` → simulasi kedaluwarsa.
///
/// Base URL sudah mencakup `/api/v1`, contoh:
/// `https://pg.miomidev.com/api/v1`.
class MiomiPayService {
  MiomiPayService({
    http.Client? client,
    String? apiKey,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _apiKeyOverride = apiKey,
       _baseUrlOverride = baseUrl;

  final http.Client _client;
  final String? _apiKeyOverride;
  final String? _baseUrlOverride;
  final Duration _timeout = const Duration(seconds: 25);

  String get _baseUrl => _baseUrlOverride ?? Config.miomiPayBaseUrl;

  String get _apiKey => _apiKeyOverride ?? Config.miomiPayApiKey;

  bool get _hasApiKey => _apiKey.trim().isNotEmpty;

  Map<String, String> get _authHeaders {
    if (!_hasApiKey) {
      throw const MiomiPayException(
        'API key MiomiPay belum diisi. Jalankan aplikasi dengan '
        '--dart-define-from-file=dart_defines.sandbox.json',
      );
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };
  }

  /// Membuat tagihan QRIS di MiomiPay.
  ///
  /// [reference] dikirim sebagai `external_id` (kode pesanan POS).
  Future<MiomiPayCharge> createCharge({
    required String reference,
    required int amount,
    String description = 'Pembayaran POS',
    String? customerName,
  }) async {
    try {
      final payload = <String, dynamic>{
        'external_id': reference,
        'amount': amount,
        'description': description,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
        if (Config.miomiPayCallbackUrl.isNotEmpty)
          'callback_url': Config.miomiPayCallbackUrl,
      };

      final response = await _client
          .post(
            Uri.parse('$_baseUrl/transactions'),
            headers: _authHeaders,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MiomiPayException(_errorFromResponse(response));
      }

      final decoded = _decode(response.body);
      if (decoded['success'] == false) {
        throw MiomiPayException(
          (decoded['message'] ?? 'MiomiPay menolak pembuatan tagihan.')
              .toString(),
        );
      }

      return _parseCharge(
        decoded,
        fallbackReference: reference,
        fallbackAmount: amount,
        offline: false,
      );
    } on MiomiPayException {
      if (Config.miomiPaySandbox) {
        return _offlineCharge(reference: reference, amount: amount);
      }
      rethrow;
    } catch (error) {
      if (Config.miomiPaySandbox) {
        return _offlineCharge(reference: reference, amount: amount);
      }
      throw MiomiPayException('Gagal menghubungi MiomiPay: $error');
    }
  }

  /// Cek status pembayaran berdasarkan snap token.
  ///
  /// Endpoint ini publik (tidak memerlukan API key).
  Future<MiomiPayCharge?> fetchCharge(String snapToken) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/transactions/$snapToken/status'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MiomiPayException(_errorFromResponse(response));
    }

    final decoded = _decode(response.body);
    if (decoded['success'] == false) return null;

    return MiomiPayCharge(
      reference: snapToken,
      transactionId: snapToken,
      amount: 0,
      status: _statusFromMap(decoded),
      qrString: snapToken,
      sandbox: (decoded['environment']?.toString().toLowerCase() ?? '') !=
          'production',
    );
  }

  /// Mengambil status saja.
  Future<MiomiPayStatus> checkStatus(String snapToken) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/transactions/$snapToken/status'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MiomiPayException(_errorFromResponse(response));
    }

    final decoded = _decode(response.body);
    return _statusFromMap(decoded);
  }

  /// Simulasi pembayaran sukses (hanya berfungsi pada lingkungan sandbox).
  Future<MiomiPayStatus> simulatePayment(String snapToken) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/sandbox/$snapToken/simulate-pay'),
          headers: _authHeaders,
          body: '{}',
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MiomiPayException(_errorFromResponse(response));
    }

    // Konfirmasi ulang lewat endpoint status agar sumber kebenaran tetap API.
    try {
      return await checkStatus(snapToken);
    } catch (_) {
      return MiomiPayStatus.paid;
    }
  }

  /// Simulasi tagihan kedaluwarsa (sandbox).
  Future<MiomiPayStatus> simulateExpire(String snapToken) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/sandbox/$snapToken/simulate-expire'),
          headers: _authHeaders,
          body: '{}',
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MiomiPayException(_errorFromResponse(response));
    }
    return MiomiPayStatus.expired;
  }

  /// MiomiPay tidak menyediakan endpoint pembatalan publik.
  /// Pembatalan cukup dilakukan di sisi aplikasi (status pesanan).
  Future<void> cancelCharge(String reference) async {
    // intentionally no-op
  }

  /// Mengecek apakah API MiomiPay dapat dijangkau.
  ///
  /// Gateway tidak menyediakan `/health`, jadi respons HTTP apa pun
  /// (termasuk 401/404) dianggap sebagai "terhubung".
  Future<bool> ping() async {
    try {
      await _client
          .get(Uri.parse(_baseUrl), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  MiomiPayCharge _parseCharge(
    Map<String, dynamic> json, {
    required String fallbackReference,
    required int fallbackAmount,
    required bool offline,
  }) {
    final data = _unwrap(json);

    final snapToken = (data['snap_token'] ??
            data['snapToken'] ??
            data['reference'] ??
            fallbackReference)
        .toString();
    final invoice = (data['reference'] ?? data['invoice_number'])?.toString();
    final status = _statusFromMap(data);
    final qr = (data['qr_string'] ??
                data['qrString'] ??
                data['qr_content'] ??
                data['qr_url'] ??
                '')
            .toString();
    final amount = _toInt(data['final_amount']) ??
        _toInt(data['amount']) ??
        fallbackAmount;
    final expiresRaw = data['expired_at'] ?? data['expires_at'];
    final environment = (data['environment'] ?? '').toString().toLowerCase();

    return MiomiPayCharge(
      reference: snapToken,
      transactionId: invoice ?? snapToken,
      invoiceReference: invoice,
      amount: amount,
      status: status,
      qrString: qr.isEmpty ? snapToken : qr,
      qrImageUrl: data['qr_image_url']?.toString(),
      checkoutUrl: data['checkout_url']?.toString(),
      expiresAt: expiresRaw is String ? DateTime.tryParse(expiresRaw) : null,
      sandbox: environment != 'production' && environment != 'live',
      offlineSimulation: offline,
    );
  }

  MiomiPayStatus _statusFromMap(Map<String, dynamic> data) {
    if (data['is_paid'] == true) return MiomiPayStatus.paid;
    if (data['is_expired'] == true) return MiomiPayStatus.expired;
    return MiomiPayStatus.fromString(
      (data['status'] ?? data['transaction_status'])?.toString(),
    );
  }

  MiomiPayCharge _offlineCharge({
    required String reference,
    required int amount,
  }) {
    return MiomiPayCharge(
      reference: 'OFFLINE-$reference',
      transactionId: 'SIM-$reference',
      invoiceReference: 'SIM-$reference',
      amount: amount,
      status: MiomiPayStatus.pending,
      qrString: 'MIOMIPAY-SANDBOX\n$reference\nRp $amount',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      sandbox: true,
      offlineSimulation: true,
    );
  }

  Map<String, dynamic> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const MiomiPayException('Respons MiomiPay tidak valid.');
    }
    return decoded;
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return json;
  }

  String _errorFromResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['message'];
        final errors = decoded['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          final detail = first is List && first.isNotEmpty
              ? first.first.toString()
              : first.toString();
          return 'MiomiPay: $detail';
        }
        if (message != null) return 'MiomiPay: $message';
      }
    } catch (_) {
      // Body bukan JSON.
    }
    return 'MiomiPay mengembalikan HTTP ${response.statusCode}.';
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
