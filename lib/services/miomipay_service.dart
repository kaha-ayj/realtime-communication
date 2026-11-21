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

/// Client API MiomiPay.
///
/// Kontrak yang dipakai aplikasi:
/// - `POST /v1/payments` membuat tagihan QRIS.
/// - `GET /v1/payments/{reference}` mengecek status pembayaran.
/// - `POST /v1/payments/{reference}/pay` mensimulasikan pembayaran (sandbox).
///
/// Secara default service mengarah ke mock server lokal. Untuk memakai API
/// asli, jalankan aplikasi dengan:
/// `--dart-define=MIOMIPAY_BASE_URL=https://...`
/// `--dart-define=MIOMIPAY_API_KEY=...`
/// `--dart-define=MIOMIPAY_SANDBOX=false`
class MiomiPayService {
  MiomiPayService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration _timeout = const Duration(seconds: 15);

  String get _baseUrl {
    final value = Config.miomiPayBaseUrl;
    return value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${Config.miomiPayApiKey}',
    'X-API-Key': Config.miomiPayApiKey,
    'X-Merchant-Id': Config.miomiPayMerchantId,
  };

  Future<MiomiPayCharge> createCharge({
    required String reference,
    required int amount,
    String description = 'Pembayaran POS',
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/v1/payments'),
            headers: _headers,
            body: jsonEncode({
              'merchant_id': Config.miomiPayMerchantId,
              'reference_id': reference,
              'amount': amount,
              'currency': 'IDR',
              'payment_method': 'QRIS',
              'description': description,
              'callback_url': 'https://pos.example.com/miomipay/callback',
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MiomiPayException(_errorFromResponse(response));
      }

      return _parseCharge(
        _decode(response.body),
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

  Future<MiomiPayStatus> checkStatus(String reference) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/v1/payments/${Uri.encodeComponent(reference)}'),
            headers: _headers,
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MiomiPayException(_errorFromResponse(response));
      }

      final data = _unwrap(_decode(response.body));
      return MiomiPayStatus.fromString(
        (data['status'] ?? data['transaction_status'])?.toString(),
      );
    } catch (error) {
      if (error is MiomiPayException) rethrow;
      throw MiomiPayException('Gagal mengecek status pembayaran: $error');
    }
  }

  Future<MiomiPayStatus> simulatePayment(String reference) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_baseUrl/v1/payments/${Uri.encodeComponent(reference)}/pay',
          ),
          headers: _headers,
          body: '{}',
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MiomiPayException(_errorFromResponse(response));
    }

    final data = _unwrap(_decode(response.body));
    return MiomiPayStatus.fromString(data['status']?.toString());
  }

  /// Mengecek apakah mock server / API MiomiPay dapat dihubungi.
  Future<bool> ping() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  MiomiPayCharge _parseCharge(
    Map<String, dynamic> json, {
    required String fallbackReference,
    required int fallbackAmount,
    required bool offline,
  }) {
    final data = _unwrap(json);
    final status = MiomiPayStatus.fromString(
      (data['status'] ?? json['status'])?.toString(),
    );
    final qr =
        (data['qr_string'] ??
                data['qr_content'] ??
                data['qrCode'] ??
                data['qr_url'] ??
                data['qr_code_url'])
            ?.toString() ??
        'MIOMIPAY|$fallbackReference|$fallbackAmount';
    final reference =
        (data['reference_id'] ??
                data['referenceId'] ??
                data['reference'] ??
                fallbackReference)
            .toString();
    final transactionId =
        (data['transaction_id'] ??
                data['transactionId'] ??
                data['id'] ??
                reference)
            .toString();
    final amount = _toInt(data['amount']) ?? fallbackAmount;
    final expiresRaw =
        data['expires_at'] ?? data['expiresAt'] ?? data['expiry_time'];
    final environment = (data['environment'] ?? data['mode'])
        ?.toString()
        .toLowerCase();

    return MiomiPayCharge(
      reference: reference,
      transactionId: transactionId,
      amount: amount,
      status: status,
      qrString: qr,
      expiresAt: expiresRaw is String ? DateTime.tryParse(expiresRaw) : null,
      sandbox: environment == 'sandbox' || Config.miomiPaySandbox,
      offlineSimulation: offline,
    );
  }

  MiomiPayCharge _offlineCharge({
    required String reference,
    required int amount,
  }) {
    return MiomiPayCharge(
      reference: reference,
      transactionId: 'SIM-$reference',
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
        final message =
            decoded['message'] ?? decoded['error'] ?? decoded['detail'];
        if (message != null) {
          return 'MiomiPay: $message';
        }
      }
    } catch (_) {
      // Abaikan body yang bukan JSON.
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
