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
      context,
    );
  }

  /// Pick a backup file and replace local data. Returns true if restored.
  Future<bool> pickAndRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return false;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return false;
    await restoreFromFile(File(path));
    return true;
  }

  Future<void> restoreFromFile(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Invalid backup file');
    }
    final map = Map<String, dynamic>.from(decoded);
    final format = map['format'] as String?;
    if (format != 'softthrive_inventory_backup') {
      throw StateError('Not an Inventory backup file');
    }

    final shop = _asMaps(map['shop_settings']);
    final categories = _asMaps(map['categories']);
    final items = _asMaps(map['inventory_items']);
    final customers = _asMaps(map['customers']);
    final sales = _asMaps(map['sales']);
    final lines = _asMaps(map['sale_lines']);
    final photosRaw = map['photos'];
    final photos = <String, String>{};
    if (photosRaw is Map) {
      photosRaw.forEach((k, v) {
        if (k is String && v is String && v.isNotEmpty) {
          photos[k] = v;
        }
      });
    }

    // Restore photos first so relative paths stay valid.
    final photosDir = await LocalImageStore.ensureDir();
    for (final entry in photos.entries) {
      final rel = entry.key;
      final name = p.basename(rel);
      final dest = File(p.join(photosDir.path, name));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(base64Decode(entry.value), flush: true);
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('sale_lines');
      await txn.delete('sales');
      await txn.delete('inventory_items');
      await txn.delete('categories');
      await txn.delete('customers');

      for (final row in categories) {
        await txn.insert(
          'categories',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in customers) {
        await txn.insert(
          'customers',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in items) {
        // Normalize photo path to relative item_photos/...
        final photo = row['photo_path'] as String?;
        final normalized = Map<String, Object?>.from(row);
        if (photo != null && photo.isNotEmpty) {
          normalized['photo_path'] = p.join(LocalImageStore.folder, p.basename(photo));
        }
        await txn.insert(
          'inventory_items',
          normalized,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in sales) {
        await txn.insert(
          'sales',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in lines) {
        final clean = Map<String, Object?>.from(row)..remove('id');
        await txn.insert('sale_lines', clean);
      }

      if (shop.isNotEmpty) {
        final settings = Map<String, Object?>.from(shop.first)..['id'] = 1;
        await txn.update('shop_settings', settings, where: 'id = 1');
      }
    });
  }

  List<Map<String, Object?>> _asMaps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v as Object?)))
        .toList();
  }
}
