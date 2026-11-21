import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:realtime_communication/models/miomipay_charge.dart';
import 'package:realtime_communication/services/miomipay_service.dart';

const _apiKey = 'MP-SB-TESTKEY';
const _base = 'https://pg.miomidev.com/api/v1';
const _successRedirect = 'https://aplikasi.test/pembayaran/sukses';

MiomiPayService _service(MockClient client) => MiomiPayService(
  client: client,
  apiKey: _apiKey,
  baseUrl: _base,
  successRedirectUrl: _successRedirect,
);

void main() {
  group('MiomiPayService.createCharge', () {
    test('mengirim request ke /payment/create dan mem-parse data', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), '$_base/payment/create');
        expect(request.headers['Authorization'], 'Bearer $_apiKey');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['external_id'], 'POS202611210001');
        expect(body['amount'], 25000);
        expect(body['customer_name'], 'Budi Santoso');
        expect(body['customer_email'], 'budi@example.com');
        expect(body['customer_phone'], '081234567890');
        expect(body['success_redirect_url'], _successRedirect);

        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Payment created successfully',
            'data': {
              'reference': 'MP-SB-ABC123XYZ',
              'invoice_number': 'INV-20261107-XXXX',
              'external_id': 'POS202611210001',
              'amount': 25000,
              'unique_amount': 25000,
              'payable_amount': 25000,
              'environment': 'sandbox',
              'payment_method': 'qris',
              'status': 'PENDING',
              'checkout_url': 'https://pg.miomidev.com/pay/snap_abc',
              'qr_image_url': 'https://pg.miomidev.com/pay/snap_abc/qr.png',
              'qr_string': '00020101021226660014ID.CO.GOPAY.WWW',
              'snap_token': 'snap_abc',
              'created_at': '2026-11-07T06:00:00Z',
              'expires_at': '2026-11-07T06:15:00Z',
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final charge = await _service(client).createCharge(
        reference: 'POS202611210001',
        amount: 25000,
        description: 'POS · POS202611210001',
        customerName: 'Budi Santoso',
        customerEmail: 'budi@example.com',
        customerPhone: '081234567890',
      );

      expect(charge.reference, 'MP-SB-ABC123XYZ');
      expect(charge.snapToken, 'snap_abc');
      expect(charge.invoiceReference, 'INV-20261107-XXXX');
      expect(charge.amount, 25000);
      expect(charge.status, MiomiPayStatus.pending);
      expect(charge.qrString, contains('GOPAY'));
      expect(charge.qrImageUrl, contains('qr.png'));
      expect(charge.checkoutUrl, contains('snap_abc'));
      expect(charge.expiresAt, isNotNull);
      expect(charge.offlineSimulation, isFalse);
      expect(charge.sandbox, isTrue);
    });

    test('mem-parse respons API sandbox yang memakai final_amount', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'reference': 'MP-INV-20261121-ZZLEIY',
              'external_id': 'POS202611210002',
              'environment': 'sandbox',
              'amount': 1000,
              'final_amount': 1000,
              'status': 'PENDING',
              'qr_string': '00020101021226660014ID.CO.GOPAY.WWW',
              'snap_token': 'snap_3HeMxR57yJaTz6SKHi48qUAiX8DZwtMO',
              'checkout_url': 'https://pg.miomidev.com/pay/snap_3HeMxR5',
              'expired_at': '2026-11-21T09:48:00+07:00',
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        ),
      );

      final charge = await _service(client).createCharge(
        reference: 'POS202611210002',
        amount: 1000,
      );

      expect(charge.reference, 'MP-INV-20261121-ZZLEIY');
      expect(charge.snapToken, 'snap_3HeMxR57yJaTz6SKHi48qUAiX8DZwtMO');
      expect(charge.invoiceReference, isNull);
      expect(charge.amount, 1000);
      expect(charge.expiresAt, isNotNull);
    });

    test('menampilkan pesan validasi 422 dari API', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'message': 'The amount field is required.',
            'errors': {
              'amount': ['The amount field is required.'],
            },
          }),
          422,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        () => _service(
          client,
        ).createCharge(reference: 'POS-ERR', amount: 1000),
        throwsA(
          isA<MiomiPayException>().having(
            (error) => error.message,
            'message',
            contains('amount'),
          ),
        ),
      );
    });

    test('fallback simulasi lokal saat jaringan gagal', () async {
      final client = MockClient((_) async => throw Exception('no network'));

      final charge = await _service(client).createCharge(
        reference: 'POS-002',
        amount: 15000,
      );

      expect(charge.offlineSimulation, isTrue);
      expect(charge.status, MiomiPayStatus.pending);
      expect(charge.amount, 15000);
      expect(charge.sandbox, isTrue);
    });
  });

  group('MiomiPayService.checkStatus', () {
    test('membaca status PAID dari respons bersarang data', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          '$_base/payment/MP-SB-ABC123XYZ/status',
        );
        expect(request.headers['Authorization'], 'Bearer $_apiKey');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'reference': 'MP-SB-ABC123XYZ',
              'status': 'PAID',
              'paid_at': '2026-11-21T23:10:28+07:00',
              'environment': 'sandbox',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        await _service(client).checkStatus('MP-SB-ABC123XYZ'),
        MiomiPayStatus.paid,
      );
    });

    test('membaca status PENDING', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'PENDING',
              'is_paid': false,
              'is_expired': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        await _service(client).checkStatus('MP-SB-PENDING'),
        MiomiPayStatus.pending,
      );
    });

    test('membaca status EXPIRED', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'EXPIRED',
              'is_paid': false,
              'is_expired': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        await _service(client).checkStatus('MP-SB-OLD'),
        MiomiPayStatus.expired,
      );
    });

    test('tetap mendukung respons status lama di root JSON', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'status': 'PAID',
            'is_paid': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        await _service(client).checkStatus('snap_abc'),
        MiomiPayStatus.paid,
      );
    });
  });

  group('MiomiPayService.simulatePayment', () {
    test('memakai snap token lalu mengonfirmasi status', () async {
      var call = 0;
      final client = MockClient((request) async {
        call++;
        if (call == 1) {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            '$_base/sandbox/snap_abc/simulate-pay',
          );
          expect(request.headers['Authorization'], 'Bearer $_apiKey');
          return http.Response(
            jsonEncode({'success': true, 'message': 'Simulasi sukses'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        expect(
          request.url.toString(),
          '$_base/payment/MP-SB-ABC123XYZ/status',
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'reference': 'MP-SB-ABC123XYZ',
              'status': 'PAID',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        await _service(client).simulatePayment(
          'MP-SB-ABC123XYZ',
          snapToken: 'snap_abc',
        ),
        MiomiPayStatus.paid,
      );
      expect(call, 2);
    });
  });

  group('MiomiPayService.ping', () {
    test('true bila gateway merespons (walau 404)', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'The route could not be found.'}),
          404,
        ),
      );
      expect(await _service(client).ping(), isTrue);
    });

    test('false bila tidak dapat dijangkau', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      expect(await _service(client).ping(), isFalse);
    });
  });

  group('MiomiPayStatus.fromString', () {
    test('memetakan variasi status gateway', () {
      expect(MiomiPayStatus.fromString('PAID'), MiomiPayStatus.paid);
      expect(MiomiPayStatus.fromString('success'), MiomiPayStatus.paid);
      expect(MiomiPayStatus.fromString('SETTLED'), MiomiPayStatus.paid);
      expect(MiomiPayStatus.fromString('EXPIRED'), MiomiPayStatus.expired);
      expect(MiomiPayStatus.fromString('CANCELLED'), MiomiPayStatus.failed);
      expect(MiomiPayStatus.fromString('PENDING'), MiomiPayStatus.pending);
      expect(MiomiPayStatus.fromString(null), MiomiPayStatus.pending);
    });
  });
}
