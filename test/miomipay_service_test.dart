import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:realtime_communication/models/miomipay_charge.dart';
import 'package:realtime_communication/services/miomipay_service.dart';

const _apiKey = 'MP-SB-TESTKEY';
const _base = 'https://pg.miomidev.com/api/v1';

MiomiPayService _service(MockClient client) =>
    MiomiPayService(client: client, apiKey: _apiKey, baseUrl: _base);

void main() {
  group('MiomiPayService.createCharge', () {
    test('mengirim request sesuai kontrak API dan mem-parse data', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), '$_base/transactions');
        expect(request.headers['Authorization'], 'Bearer $_apiKey');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['external_id'], 'POS202611210001');
        expect(body['amount'], 25000);

        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'reference': 'MP-INV-20261121-ABC123',
              'external_id': 'POS202611210001',
              'environment': 'sandbox',
              'amount': 25000,
              'final_amount': 25000,
              'status': 'PENDING',
              'qr_string': '00020101021226660014ID.CO.GOPAY.WWW',
              'qr_image_url': 'https://pg.miomidev.com/pay/snap_abc/qr.png',
              'snap_token': 'snap_abc',
              'checkout_url': 'https://pg.miomidev.com/pay/snap_abc',
              'expired_at': '2026-11-21T23:23:24+07:00',
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final charge = await _service(client).createCharge(
        reference: 'POS202611210001',
        amount: 25000,
      );

      expect(charge.reference, 'snap_abc');
      expect(charge.invoiceReference, 'MP-INV-20261121-ABC123');
      expect(charge.amount, 25000);
      expect(charge.status, MiomiPayStatus.pending);
      expect(charge.qrString, contains('GOPAY'));
      expect(charge.qrImageUrl, contains('qr.png'));
      expect(charge.checkoutUrl, contains('snap_abc'));
      expect(charge.offlineSimulation, isFalse);
      expect(charge.sandbox, isTrue);
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

      // Mode sandbox aktif → fallback offline, bukan melempar error.
      final charge = await _service(client).createCharge(
        reference: 'POS-ERR',
        amount: 1000,
      );
      expect(charge.offlineSimulation, isTrue);
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
    test('membaca status PAID', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          '$_base/transactions/snap_abc/status',
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'status': 'PAID',
            'is_paid': true,
            'is_expired': false,
            'paid_at': '2026-11-21T23:10:28+07:00',
            'environment': 'sandbox',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        await _service(client).checkStatus('snap_abc'),
        MiomiPayStatus.paid,
      );
    });

    test('membaca status PENDING', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'status': 'PENDING',
            'is_paid': false,
            'is_expired': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        await _service(client).checkStatus('snap_xyz'),
        MiomiPayStatus.pending,
      );
    });

    test('membaca status EXPIRED', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'status': 'EXPIRED',
            'is_paid': false,
            'is_expired': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        await _service(client).checkStatus('snap_old'),
        MiomiPayStatus.expired,
      );
    });
  });

  group('MiomiPayService.simulatePayment', () {
    test('memanggil simulate-pay lalu mengonfirmasi status', () async {
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
          '$_base/transactions/snap_abc/status',
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'status': 'PAID',
            'is_paid': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        await _service(client).simulatePayment('snap_abc'),
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
