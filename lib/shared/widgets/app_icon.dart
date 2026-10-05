import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Client-provided icons from `assets/svg/` (PNG = transparent BG).
class AppAssets {
  AppAssets._();

  static const inventory = 'assets/svg/inventory.png';
  static const customer = 'assets/svg/customer.png';
  static const turnover = 'assets/svg/turnover.png';
  static const settings = 'assets/svg/settings.png';
  static const qrScanner = 'assets/svg/qrscaner.png';
  static const data = 'assets/svg/data.png';
  static const security = 'assets/svg/security.png';
  static const search = 'assets/svg/search-normal.svg';
  static const filter = 'assets/svg/filter.svg';
  static const sort = 'assets/svg/sort.svg';
  static const edit = 'assets/svg/edit.svg';

  // Colorful brand icons (transparent BG) — do not tint with color.
  static const phone = 'assets/images/icons/phone.svg';
  static const email = 'assets/images/icons/email.svg';
  static const notes = 'assets/images/icons/notes.svg';
  static const whatsapp = 'assets/images/icons/whatsapp.svg';
  static const facebook = 'assets/images/icons/facebook.svg';
  static const instagram = 'assets/images/icons/instagram.svg';
  static const linkedin = 'assets/images/icons/linkedin.svg';
  static const telegram = 'assets/images/icons/telegram.svg';
}

/// Renders JPG/PNG/SVG assets with a consistent size.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.asset, {
    super.key,
    this.size = 26,
    this.color,
    this.opacity = 1,
  });

  final String asset;
  final double size;
  final Color? color;
  final double opacity;

  bool get _isSvg => asset.toLowerCase().endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_isSvg) {
      child = SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: color == null
            ? null
            : ColorFilter.mode(color!, BlendMode.srcIn),
      );
    } else {
      final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 3;
      final cache = (size * dpr * 2).round().clamp(64, 1024);
      final img = Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        gaplessPlayback: true,
        cacheWidth: cache,
        cacheHeight: cache,
        errorBuilder: (_, __, ___) => Icon(
          Icons.broken_image_outlined,
          size: size,
          color: color ?? Colors.grey,
        ),
      );
      child = color == null
          ? img
          : ColorFiltered(
              colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
              child: img,
            );
    }

    if (opacity >= 0.999) return child;
    return Opacity(opacity: opacity, child: child);
  }
}
