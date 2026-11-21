import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/miomipay_charge.dart';

class MiomiPayException implements Exception {
  const MiomiPayException(this.message, {this.isNetworkError = false});

  final String message;

  /// True bila request gagal karena masalah jaringan/timeout, bukan karena
  /// validasi atau autentikasi dari gateway.
  final bool isNetworkError;

  @override
  String toString() => message;
}

/// Client API MiomiPay (https://pg.miomidev.com).
///
/// Kontrak yang dipakai:
/// - `POST /payment/create` (Bearer API key) → membuat tagihan QRIS.
/// - `GET  /payment/{reference}/status` (Bearer API key) → status pembayaran.
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
    String? successRedirectUrl,
  }) : _client = client ?? http.Client(),
       _apiKeyOverride = apiKey,
       _baseUrlOverride = baseUrl,
       _successRedirectUrlOverride = successRedirectUrl;

  final http.Client _client;
  final String? _apiKeyOverride;
  final String? _baseUrlOverride;
  final String? _successRedirectUrlOverride;
  final Duration _timeout = const Duration(seconds: 25);

  String get _baseUrl => _baseUrlOverride ?? Config.miomiPayBaseUrl;

  String get _apiKey => _apiKeyOverride ?? Config.miomiPayApiKey;

  bool get _hasApiKey => _apiKey.trim().isNotEmpty;

  String get _successRedirectUrl =>
      _successRedirectUrlOverride ?? Config.miomiPaySuccessRedirectUrl;

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
    String? customerEmail,
    String? customerPhone,
  }) async {
    if (!_hasApiKey && Config.miomiPaySandbox) {
      return _offlineCharge(reference: reference, amount: amount);
    }

    try {
      final payload = <String, dynamic>{
        'external_id': reference,
        'amount': amount,
        'description': description,
        if (_nonEmpty(customerName) != null)
          'customer_name': _nonEmpty(customerName),
        if (_nonEmpty(customerEmail) != null)
          'customer_email': _nonEmpty(customerEmail),
        if (_nonEmpty(customerPhone) != null)
          'customer_phone': _nonEmpty(customerPhone),
        if (_successRedirectUrl.trim().isNotEmpty)
          'success_redirect_url': _successRedirectUrl.trim(),
      };

      final response = await _client
          .post(
            Uri.parse('$_baseUrl/payment/create'),
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
      // Kesalahan validasi/autentikasi tidak boleh disamarkan sebagai
      // pembayaran offline.
      rethrow;
    } catch (error) {
      if (Config.miomiPaySandbox) {
        return _offlineCharge(reference: reference, amount: amount);
      }
      throw MiomiPayException(
        'Gagal menghubungi MiomiPay: $error',
        isNetworkError: true,
      );
    }
  }

  /// Mengambil detail tagihan terbaru berdasarkan reference gateway.
  Future<MiomiPayCharge> fetchCharge(String reference) async {
    final data = await _fetchStatus(reference);
    return _parseCharge(
      data,
      fallbackReference: reference,
      fallbackAmount: 0,
      offline: false,
    );
  }

  /// Mengambil status saja.
  Future<MiomiPayStatus> checkStatus(String reference) async {
    final data = await _fetchStatus(reference);
    return _statusFromMap(data);
  }

  Future<Map<String, dynamic>> _fetchStatus(String reference) async {
    final response = await _client
        .get(
          Uri.parse(
            '$_baseUrl/payment/${Uri.encodeComponent(reference)}/status',
          ),
          headers: _authHeaders,
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MiomiPayException(_errorFromResponse(response));
    }

    final decoded = _decode(response.body);
    if (decoded['success'] == false) {
      throw MiomiPayException(
        (decoded['message'] ?? 'Status transaksi MiomiPay tidak ditemukan.')
            .toString(),
      );
    }

    return _unwrap(decoded);
  }

  /// Simulasi pembayaran sukses (hanya berfungsi pada lingkungan sandbox).
  ///
  /// Simulasi membutuhkan `snap_token`. Bila tidak tersedia, [reference]
  /// dipakai sebagai fallback (API lama menerima keduanya).
  Future<MiomiPayStatus> simulatePayment(
    String reference, {
    String? snapToken,
  }) async {
    final token = _simulationToken(reference, snapToken);
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/sandbox/$token/simulate-pay'),
          headers: _authHeaders,
          body: '{}',
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MiomiPayException(_errorFromResponse(response));
    }

    // Konfirmasi ulang lewat endpoint status agar sumber kebenaran tetap API.
    try {
      return await checkStatus(reference);
    } catch (_) {
      return MiomiPayStatus.paid;
    }
  }

  /// Simulasi tagihan kedaluwarsa (sandbox).
  Future<MiomiPayStatus> simulateExpire(
    String reference, {
    String? snapToken,
  }) async {
    final token = _simulationToken(reference, snapToken);
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/sandbox/$token/simulate-expire'),
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
          .get(
            Uri.parse(_baseUrl),
            headers: const {'Accept': 'application/json'},
          )
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

    final snapToken =
        _nonEmpty(data['snap_token']) ?? _nonEmpty(data['snapToken']);
    final gatewayReference =
        _nonEmpty(data['reference']) ?? snapToken ?? fallbackReference;
    final invoice = _nonEmpty(data['invoice_number']);
    final status = _statusFromMap(data);
    final qr =
        _nonEmpty(data['qr_string']) ??
        _nonEmpty(data['qrString']) ??
        _nonEmpty(data['qr_content']) ??
        _nonEmpty(data['qr_url']) ??
        '';
    final amount = _amountFrom(data) ?? fallbackAmount;
    final expiresRaw = data['expires_at'] ?? data['expired_at'];
    final environment = (data['environment'] ?? '').toString().toLowerCase();
    final externalId = _nonEmpty(data['external_id']);

    return MiomiPayCharge(
      reference: gatewayReference,
      snapToken: snapToken,
      transactionId: externalId ?? gatewayReference,
      invoiceReference: invoice,
      amount: amount,
      status: status,
      qrString: qr.isEmpty ? gatewayReference : qr,
      qrImageUrl: _nonEmpty(data['qr_image_url']),
      checkoutUrl: _nonEmpty(data['checkout_url']),
      expiresAt: expiresRaw is String ? DateTime.tryParse(expiresRaw) : null,
      sandbox: environment != 'production' && environment != 'live',
      offlineSimulation: offline,
    );
  }

  MiomiPayStatus _statusFromMap(Map<String, dynamic> raw) {
    final data = _unwrap(raw);
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

  int? _amountFrom(Map<String, dynamic> data) {
    return _toInt(data['payable_amount']) ??
        _toInt(data['unique_amount']) ??
        _toInt(data['final_amount']) ??
        _toInt(data['amount']);
  }

  String _simulationToken(String reference, String? snapToken) {
    final token = snapToken?.trim() ?? '';
    return token.isEmpty ? reference : token;
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

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
