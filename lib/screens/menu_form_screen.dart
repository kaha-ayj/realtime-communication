import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/menu_item.dart';
import '../providers/app_provider.dart';
import '../thema.dart';
import '../widgets/common_widgets.dart';
import '../widgets/menu_photo.dart';

class MenuFormScreen extends StatefulWidget {
  const MenuFormScreen({super.key, this.menu});

  /// Null berarti mode tambah, non-null berarti mode edit.
  final MenuItem? menu;

  @override
  State<MenuFormScreen> createState() => _MenuFormScreenState();
}

class _MenuFormScreenState extends State<MenuFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _emojiCtrl;
  late final TextEditingController _imageCtrl;
  late String _category;
  late bool _isAvailable;
  bool _loading = false;

  static const _categories = [
    'Makanan',
    'Minuman',
    'Camilan',
    'Dessert',
    'Lainnya',
  ];

  static const _quickEmojis = [
    '🍛', '🍜', '🍲', '🍗', '🍢', '🌮', '🥗', '🍳',
    '🍔', '🌯', '🥩', '🍱', '🍝', '🥘', '🫕', '🍲',
    '☕', '🍵', '🧋', '🥤', '🍊', '🧃', '🧊', '💧',
    '🍟', '🌽', '🍌', '🍫', '🍰', '🧁', '🍩', '🍮',
  ];

  bool get _isEdit => widget.menu != null;

  @override
  void initState() {
    super.initState();
    final m = widget.menu;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _priceCtrl = TextEditingController(
      text: m != null ? '${m.price}' : '',
    );
    _descCtrl = TextEditingController(text: m?.description ?? '');
    _emojiCtrl = TextEditingController(text: m?.emoji ?? '🍽️');
    _imageCtrl = TextEditingController(text: m?.imageUrl ?? '');
    _category = m?.category ?? 'Makanan';
    _isAvailable = m?.isAvailable ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _emojiCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final menuService = context.read<AppProvider>().menuService;
      final menu = MenuItem(
        id: widget.menu?.id ?? '',
        name: _nameCtrl.text.trim(),
        category: _category,
        price: int.parse(_priceCtrl.text.trim()),
        description: _descCtrl.text.trim(),
        emoji: _emojiCtrl.text.trim().isEmpty ? '🍽️' : _emojiCtrl.text.trim(),
        imageUrl: _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
        isAvailable: _isAvailable,
      );

      if (_isEdit) {
        await menuService.updateMenu(menu);
      } else {
        await menuService.addMenu(menu);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? '"${menu.name}" berhasil diperbarui.' : '"${menu.name}" berhasil ditambahkan.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: PosColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Menu' : 'Tambah Menu'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            // Pratinjau foto produk
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: Listenable.merge([_nameCtrl, _imageCtrl]),
                    builder: (context, _) {
                      return Container(
                        width: 108,
                        height: 108,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: PosColors.border),
                        ),
                        child: ProductPhoto(
                          name: _nameCtrl.text,
                          imageUrl: _imageCtrl.text,
                          emoji: _emojiCtrl.text.isEmpty
                              ? '🍽️'
                              : _emojiCtrl.text,
                          width: 100,
                          height: 100,
                          borderRadius: 22,
                          emojiSize: 46,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pratinjau foto produk',
                    style: TextStyle(fontSize: 12, color: PosColors.textMuted),
                  ),
                  TextButton.icon(
                    onPressed: () => _showEmojiPicker(context),
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 14),
                    label: const Text('Emoji cadangan'),
                    style: TextButton.styleFrom(
                      foregroundColor: PosColors.textMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _label('Nama Menu'),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Contoh: Nasi Goreng Spesial',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Nama menu wajib diisi';
                if (v.trim().length < 2) return 'Nama terlalu pendek';
                return null;
              },
            ),
            const SizedBox(height: 16),

            _label('URL Foto Produk (opsional)'),
            TextFormField(
              controller: _imageCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://contoh.com/foto-produk.jpg',
                prefixIcon: const Icon(Icons.image_outlined),
                helperText:
                    'Kosongkan agar foto dipilih otomatis sesuai nama menu.',
                helperMaxLines: 2,
                suffixIcon: ListenableBuilder(
                  listenable: _imageCtrl,
                  builder: (context, _) {
                    if (_imageCtrl.text.trim().isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      tooltip: 'Hapus URL foto',
                      onPressed: () => _imageCtrl.clear(),
                      icon: const Icon(Icons.close_rounded),
                    );
                  },
                ),
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return null;
                final uri = Uri.tryParse(value);
                if (uri == null ||
                    !(uri.isScheme('http') || uri.isScheme('https'))) {
                  return 'URL foto harus diawali http:// atau https://';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            _label('Kategori'),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: PosColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: PosColors.border),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'Makanan'),
            ),
            const SizedBox(height: 16),

            _label('Harga (Rp)'),
            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'Contoh: 25000',
                prefixText: 'Rp ',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Harga wajib diisi';
                final parsed = int.tryParse(v.trim());
                if (parsed == null || parsed <= 0) return 'Harga harus lebih dari 0';
                if (parsed > 10000000) return 'Harga terlalu besar';
                return null;
              },
            ),
            const SizedBox(height: 16),

            _label('Deskripsi (opsional)'),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Deskripsi singkat menu ini…',
              ),
            ),
            const SizedBox(height: 20),

            // Toggle tersedia
            Card(
              child: SwitchListTile(
                activeThumbColor: PosColors.primary,
                title: const Text(
                  'Tersedia untuk dijual',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  _isAvailable
                      ? 'Menu akan muncul di halaman kasir'
                      : 'Menu disembunyikan dari kasir',
                  style: const TextStyle(fontSize: 12, color: PosColors.textMuted),
                ),
                value: _isAvailable,
                onChanged: (v) => setState(() => _isAvailable = v),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          child: PosButton(
            label: _isEdit ? 'Simpan Perubahan' : 'Tambah Menu',
            icon: _isEdit ? Icons.save_rounded : Icons.add_rounded,
            loading: _loading,
            onPressed: _save,
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
          color: PosColors.text,
        ),
      ),
    );
  }

  void _showEmojiPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pilih Emoji',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _quickEmojis
                  .map(
                    (e) => GestureDetector(
                      onTap: () {
                        setState(() => _emojiCtrl.text = e);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: _emojiCtrl.text == e
                              ? PosColors.primarySoft
                              : const Color(0xFFF7F6F2),
                          borderRadius: BorderRadius.circular(14),
                          border: _emojiCtrl.text == e
                              ? Border.all(color: PosColors.primary)
                              : null,
                        ),
                        child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
