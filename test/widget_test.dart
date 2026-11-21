import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_communication/services/order.dart';

void main() {
  test('formatCurrency formats Rupiah correctly', () {
    expect(formatCurrency(25000), 'Rp 25.000');
    expect(formatCurrency(1500000), 'Rp 1.500.000');
    expect(formatCurrency(0), 'Rp 0');
  });
}
