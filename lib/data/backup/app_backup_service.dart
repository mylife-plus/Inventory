import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:inventory_app/core/media/local_image_store.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

List<Map<String, Object?>> _asMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v as Object?)))
      .toList();
}

/// Top-level for [compute] — keep heavy JSON off the UI thread.
/// Returns a plain map so the isolate transfer stays reliable.
Map<String, Object?> _parseBackupIsolate(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw StateError('Invalid backup file');
  }
  final map = Map<String, dynamic>.from(decoded);
  final format = map['format'] as String?;
  if (format != 'softthrive_inventory_backup') {
    throw StateError('Not an Inventory backup file');
  }

  final photosRaw = map['photos'];
  final photos = <String, String>{};
  if (photosRaw is Map) {
    photosRaw.forEach((k, v) {
      if (k is String && v is String && v.isNotEmpty) {
        photos[k] = v;
      }
    });
  }

  return <String, Object?>{
    'shop_settings': _asMaps(map['shop_settings']),
    'categories': _asMaps(map['categories']),
    'inventory_items': _asMaps(map['inventory_items']),
    'customers': _asMaps(map['customers']),
    'sales': _asMaps(map['sales']),
    'sale_lines': _asMaps(map['sale_lines']),
    'photos': photos,
  };
}

/// Full offline backup / restore of shop data (DB tables + product photos).
class AppBackupService {
  AppBackupService(this._db);

  final AppDatabase _db;

  static const formatVersion = 1;
  static const fileExtension = 'inventorybak';

  Future<File> exportToFile() async {
    final db = await _db.database;
    final shop = await db.query('shop_settings');
    final categories = await db.query('categories');
    final items = await db.query('inventory_items');
    final customers = await db.query('customers');
    final sales = await db.query('sales');
    final lines = await db.query('sale_lines');

    final photos = <String, String>{};
    for (final row in [...items, ...customers]) {
      final rel = row['photo_path'] as String?;
      if (rel == null || rel.trim().isEmpty) continue;
      if (photos.containsKey(rel)) continue;
      final resolved = await LocalImageStore.resolve(rel);
      if (resolved == null) continue;
      final bytes = await File(resolved).readAsBytes();
      photos[rel] = base64Encode(bytes);
    }

    final payload = <String, Object?>{
      'format': 'softthrive_inventory_backup',
      'version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'shop_settings': shop,
      'categories': categories,
      'inventory_items': items,
      'customers': customers,
      'sales': sales,
      'sale_lines': lines,
      'photos': photos,
    };

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      p.join(dir.path, 'inventory_backup_$stamp.$fileExtension'),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  Future<void> shareBackup({BuildContext? context, String? shareText}) async {
    final file = await exportToFile();
    await shareWithOrigin(
      ShareParams(
        files: [XFile(file.path)],
        text: shareText ?? 'Inventory app data backup',
      ),
      (context != null && context.mounted) ? context : null,
    );
  }

  /// Open the system picker for a backup file.
  ///
  /// Any file type: our `.inventorybak` extension has no registered type on
  /// iOS (dyn. UTI) or Android (no MIME), so file_picker drops it from an
  /// extension filter and the saved backup showed up greyed out / unpickable.
  /// The content is validated on restore (`format` field) instead.
  static Future<PlatformFile?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single;
  }

  /// Read backup text from a [PlatformFile] (bytes preferred; path fallback).
  /// Returns `null` when neither bytes nor a readable path are available.
  static Future<String?> readPickedBackup(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return utf8.decode(bytes);
    }
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    // dart:io File — unavailable / path-null on web; bytes path covers that.
    if (kIsWeb) return null;
    return File(path).readAsString();
  }

  /// Pick a backup (`.inventorybak` / `.json`) and replace local data.
  /// Returns a label for the chosen file after restore, or `null` if cancelled.
  Future<String?> pickAndRestore({bool awaitPhotos = true}) async {
    final chosen = await pickBackupFile();
    if (chosen == null) return null;
    final raw = await readPickedBackup(chosen);
    if (raw == null || raw.isEmpty) return null;
    await restoreFromJson(raw, awaitPhotos: awaitPhotos);
    return chosen.name;
  }

  Future<void> restoreFromFile(
    File file, {
    bool awaitPhotos = true,
  }) async {
    await restoreFromJson(await file.readAsString(), awaitPhotos: awaitPhotos);
  }

  /// When [awaitPhotos] is false, table data is ready as soon as this returns
  /// and photo files continue writing in the background.
  Future<void> restoreFromJson(
    String raw, {
    bool awaitPhotos = true,
  }) async {
    // Large demos: parse off the UI isolate so the UI stays responsive.
    final parsed = await compute(_parseBackupIsolate, raw);
    await _applyTables(parsed);
    final photosFuture = _applyPhotos(parsed);
    if (awaitPhotos) {
      await photosFuture;
    } else {
      // ignore: unawaited_futures
      photosFuture;
    }
  }

  Future<void> _applyTables(Map<String, Object?> parsed) async {
    final shop = _asMaps(parsed['shop_settings']);
    final categories = _asMaps(parsed['categories']);
    final items = _asMaps(parsed['inventory_items']);
    final customers = _asMaps(parsed['customers']);
    final sales = _asMaps(parsed['sales']);
    final lines = _asMaps(parsed['sale_lines']);

    final db = await _db.database;

    // One SQLite batch so inventory/sales/customers are queryable immediately.
    await db.transaction((txn) async {
      await txn.delete('sale_lines');
      await txn.delete('sales');
      await txn.delete('inventory_items');
      await txn.delete('categories');
      await txn.delete('customers');

      final batch = txn.batch();

      for (final row in categories) {
        batch.insert(
          'categories',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in customers) {
        batch.insert(
          'customers',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in items) {
        final photo = row['photo_path'] as String?;
        final normalized = Map<String, Object?>.from(row);
        if (photo != null && photo.isNotEmpty) {
          normalized['photo_path'] = p.join(
            LocalImageStore.folder,
            p.basename(photo),
          );
        }
        batch.insert(
          'inventory_items',
          normalized,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in sales) {
        batch.insert(
          'sales',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in lines) {
        final clean = Map<String, Object?>.from(row)..remove('id');
        batch.insert('sale_lines', clean);
      }

      await batch.commit(noResult: true);

      if (shop.isNotEmpty) {
        final settings = Map<String, Object?>.from(shop.first)..['id'] = 1;
        await txn.update('shop_settings', settings, where: 'id = 1');
      }
    });
  }

  Future<void> _applyPhotos(Map<String, Object?> parsed) async {
    // Web has no documents directory / dart:io photo store.
    if (kIsWeb) return;

    final photosRaw = parsed['photos'];
    final photos = <String, String>{};
    if (photosRaw is Map) {
      photosRaw.forEach((k, v) {
        if (k is String && v is String && v.isNotEmpty) photos[k] = v;
      });
    }
    if (photos.isEmpty) return;

    final photosDir = await LocalImageStore.ensureDir();
    await Future.wait(
      photos.entries.map((entry) async {
        final name = p.basename(entry.key);
        final dest = File(p.join(photosDir.path, name));
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(base64Decode(entry.value), flush: false);
      }),
      eagerError: false,
    );
  }
}
