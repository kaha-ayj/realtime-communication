/// Foto produk bawaan, dipetakan otomatis dari nama menu.
///
/// Tujuannya agar setiap produk langsung punya foto yang sesuai dengan
/// namanya tanpa admin harus mengisi URL satu per satu. Admin tetap bisa
/// mengganti foto lewat kolom "URL Foto" pada form menu.
class MenuImages {
  MenuImages._();

  static const String _base =
      'https://upload.wikimedia.org/wikipedia/commons/thumb';

  // Nama keyword -> URL foto. Dicek berurutan, jadi taruh yang paling
  // spesifik di atas (mis. "es jeruk" sebelum "jeruk").
  static const List<(String, String)> _rules = [
    (
      'nasi goreng',
      '$_base/3/3e/Nasi_goreng_indonesia.jpg'
          '/960px-Nasi_goreng_indonesia.jpg',
    ),
    (
      'ayam geprek',
      '$_base/2/2e/Ayam_geprek_pedas.jpg'
          '/960px-Ayam_geprek_pedas.jpg',
    ),
    (
      'geprek',
      '$_base/2/2e/Ayam_geprek_pedas.jpg'
          '/960px-Ayam_geprek_pedas.jpg',
    ),
    (
      'mie goreng',
      '$_base/f/f9/Mie_goreng.jpg/960px-Mie_goreng.jpg',
    ),
    (
      'mi goreng',
      '$_base/f/f9/Mie_goreng.jpg/960px-Mie_goreng.jpg',
    ),
    (
      'bakso',
      '$_base/6/6e/Bakso_Indonesian_Meatball_Soup_from_Solo.jpg'
          '/960px-Bakso_Indonesian_Meatball_Soup_from_Solo.jpg',
    ),
    (
      'sate',
      '$_base/4/44/Sate_Ayam_Panggang.jpg'
          '/960px-Sate_Ayam_Panggang.jpg',
    ),
    (
      'es teh',
      '$_base/e/ef/Iced_Tea_from_flickr.jpg'
          '/960px-Iced_Tea_from_flickr.jpg',
    ),
    (
      'es jeruk',
      '$_base/6/66/Es_jeruk.jpg/960px-Es_jeruk.jpg',
    ),
    (
      'jeruk',
      '$_base/6/66/Es_jeruk.jpg/960px-Es_jeruk.jpg',
    ),
    (
      'kopi',
      '$_base/5/54/Es_kopi_susu_kekinian_di_Yogyakarta%2C_Indonesia.jpg'
          '/960px-Es_kopi_susu_kekinian_di_Yogyakarta%2C_Indonesia.jpg',
    ),
    (
      'matcha',
      '$_base/c/ce/Matcha_latte_in_tall_glass.jpg'
          '/960px-Matcha_latte_in_tall_glass.jpg',
    ),
    (
      'kentang',
      '$_base/6/65/Kentang_Goreng_Neat.Co.jpg'
          '/960px-Kentang_Goreng_Neat.Co.jpg',
    ),
    (
      'pisang',
      '$_base/b/b9/Pisang_Goreng_dipiring.jpg'
          '/960px-Pisang_Goreng_dipiring.jpg',
    ),
    (
      'brownies',
      '$_base/3/35/Chocolate_brownies.jpg'
          '/960px-Chocolate_brownies.jpg',
    ),
    (
      'brownie',
      '$_base/3/35/Chocolate_brownies.jpg'
          '/960px-Chocolate_brownies.jpg',
    ),
    (
      'cheesecake',
      '$_base/9/9c/Mondays_at_Il_Forno_-_Cheesecake_with_strawberry_sauce.jpg'
          '/960px-Mondays_at_Il_Forno_-_Cheesecake_with_strawberry_sauce.jpg',
    ),
    (
      'air mineral',
      '$_base/3/37/Botol_air_mineral.jpg'
          '/960px-Botol_air_mineral.jpg',
    ),
    (
      'teh',
      '$_base/e/ef/Iced_Tea_from_flickr.jpg'
          '/960px-Iced_Tea_from_flickr.jpg',
    ),
  ];

  /// URL foto yang cocok dengan [name], atau `null` bila tidak ada.
  static String? forName(String name) {
    final key = _normalize(name);
    if (key.isEmpty) return null;
    for (final rule in _rules) {
      if (key.contains(rule.$1)) return rule.$2;
    }
    return null;
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}
