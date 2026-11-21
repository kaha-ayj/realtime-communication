import 'package:flutter/material.dart';

import '../data/menu_images.dart';
import '../models/menu_item.dart';
import '../thema.dart';

/// Foto produk dengan fallback otomatis ke emoji.
///
/// Urutan sumber foto:
/// 1. [imageUrl] (diisi admin lewat form menu),
/// 2. foto bawaan yang dicocokkan dari [name],
/// 3. emoji sebagai placeholder bila gambar tidak tersedia/gagal dimuat.
class ProductPhoto extends StatelessWidget {
  const ProductPhoto({
    super.key,
    required this.name,
    this.imageUrl,
    this.emoji = '🍽️',
    this.width,
    this.height,
    this.borderRadius = 14,
    this.emojiSize = 28,
    this.backgroundColor = PosColors.primarySoft,
  });

  final String name;
  final String? imageUrl;
  final String emoji;
  final double? width;
  final double? height;
  final double borderRadius;
  final double emojiSize;
  final Color backgroundColor;

  String? get _resolvedUrl {
    final custom = imageUrl?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return MenuImages.forName(name);
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl;
    final radius = BorderRadius.circular(borderRadius);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? _EmojiFallback(
                emoji: emoji,
                fontSize: emojiSize,
                backgroundColor: backgroundColor,
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: (width != null && width!.isFinite)
                    ? (width! * MediaQuery.devicePixelRatioOf(context)).round()
                    : null,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _PhotoPlaceholder(
                    backgroundColor: backgroundColor,
                    progress: progress,
                  );
                },
                errorBuilder: (_, _, _) => _EmojiFallback(
                  emoji: emoji,
                  fontSize: emojiSize,
                  backgroundColor: backgroundColor,
                ),
              ),
      ),
    );
  }
}

/// Foto produk dari [MenuItem].
class MenuPhoto extends StatelessWidget {
  const MenuPhoto({
    super.key,
    required this.menu,
    this.width,
    this.height,
    this.borderRadius = 14,
    this.emojiSize = 28,
    this.backgroundColor = PosColors.primarySoft,
  });

  final MenuItem menu;
  final double? width;
  final double? height;
  final double borderRadius;
  final double emojiSize;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ProductPhoto(
      name: menu.name,
      imageUrl: menu.imageUrl,
      emoji: menu.emoji,
      width: width,
      height: height,
      borderRadius: borderRadius,
      emojiSize: emojiSize,
      backgroundColor: backgroundColor,
    );
  }
}

class _EmojiFallback extends StatelessWidget {
  const _EmojiFallback({
    required this.emoji,
    required this.fontSize,
    required this.backgroundColor,
  });

  final String emoji;
  final double fontSize;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: fontSize)),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({
    required this.backgroundColor,
    required this.progress,
  });

  final Color backgroundColor;
  final ImageChunkEvent progress;

  @override
  Widget build(BuildContext context) {
    final expected = progress.expectedTotalBytes;
    final value = expected != null
        ? progress.cumulativeBytesLoaded / expected
        : null;

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: value,
            color: PosColors.primary,
          ),
        ),
      ),
    );
  }
}
