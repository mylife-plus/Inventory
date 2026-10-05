import 'dart:io';

import 'package:flutter/material.dart';
import 'package:inventory_app/core/media/local_image_store.dart';
import 'package:inventory_app/core/theme/app_theme.dart';

/// Loads a DB-stored photo path (relative or absolute) and shows it.
class LocalPhoto extends StatelessWidget {
  const LocalPhoto({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.image_rounded,
  });

  final String? path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return FutureBuilder<String?>(
      future: LocalImageStore.resolve(path),
      builder: (context, snap) {
        final resolved = snap.data;
        final Widget image;
        if (resolved == null) {
          // Same footprint as a real photo — fills parent, centered icon.
          image = ColoredBox(
            color: p.cardElevated,
            child: Center(
              child: Icon(placeholderIcon, color: p.textMuted, size: 30),
            ),
          );
        } else {
          image = Image.file(
            File(resolved),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: p.cardElevated,
              child: Center(
                child: Icon(placeholderIcon, color: p.textMuted, size: 30),
              ),
            ),
          );
        }

        Widget child = SizedBox.expand(child: image);
        if (width != null || height != null) {
          child = SizedBox(width: width, height: height, child: image);
        }

        if (borderRadius != null) {
          return ClipRRect(borderRadius: borderRadius!, child: child);
        }
        return child;
      },
    );
  }
}
