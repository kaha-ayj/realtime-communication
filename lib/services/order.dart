// Re-export OrderService from auth_service.dart and provide formatCurrency helper.
export 'auth_service.dart' show OrderService;

/// Format integer (e.g. 25000) as Indonesian Rupiah string: "Rp 25.000"
String formatCurrency(int amount) {
  final str = amount.toString();
  final buffer = StringBuffer('Rp ');
  final len = str.length;
  for (var i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buffer.write('.');
    buffer.write(str[i]);
  }
  return buffer.toString();
}
