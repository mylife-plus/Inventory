import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists product photos under app documents so they survive restarts.
/// DB stores a relative path like `item_photos/abc.jpg`.
class LocalImageStore {
  LocalImageStore._();

  static const folder = 'item_photos';

  static Future<Directory> ensureDir() => _photosDir();

  static Future<Directory> _photosDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copy camera/gallery pick into permanent storage. Returns relative path.
  static Future<String> savePicked(
    XFile file, {
    String? itemId,
  }) async {
    final dir = await _photosDir();
    final ext = _safeExt(file.path, file.mimeType);
    final name = '${itemId ?? newId()}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = File(p.join(dir.path, name));
    final bytes = await file.readAsBytes();
    await dest.writeAsBytes(bytes, flush: true);
    return p.join(folder, name);
  }

  static String _safeExt(String path, String? mime) {
    final fromPath = p.extension(path).toLowerCase();
    if (fromPath == '.jpg' ||
        fromPath == '.jpeg' ||
        fromPath == '.png' ||
        fromPath == '.heic' ||
        fromPath == '.webp') {
      return fromPath == '.jpeg' ? '.jpg' : fromPath;
    }
    if (mime != null) {
      if (mime.contains('png')) return '.png';
      if (mime.contains('webp')) return '.webp';
      if (mime.contains('heic')) return '.heic';
    }
    return '.jpg';
  }

  /// Resolve DB path (relative or legacy absolute) to an existing local file.
  static Future<String?> resolve(String? stored) async {
    if (stored == null || stored.trim().isEmpty) return null;
    final value = stored.trim();

    if (p.isAbsolute(value)) {
      final abs = File(value);
      if (await abs.exists()) return abs.path;
      // Legacy absolute path may break after reinstall — try basename.
      final dir = await _photosDir();
      final fallback = File(p.join(dir.path, p.basename(value)));
      if (await fallback.exists()) return fallback.path;
      return null;
    }

    final root = await getApplicationDocumentsDirectory();
    final full = File(p.join(root.path, value));
    if (await full.exists()) return full.path;

    // Stored as bare filename
    final dir = await _photosDir();
    final byName = File(p.join(dir.path, p.basename(value)));
    if (await byName.exists()) return byName.path;
    return null;
  }

  static Future<void> delete(String? stored) async {
    final path = await resolve(stored);
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
