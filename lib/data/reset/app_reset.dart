import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/app.dart';
import 'package:inventory_app/core/media/local_image_store.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/sync/sync_controller.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:inventory_app/data/resale_draft.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Settings > Reset App: erase user business data (items, sales, customers,
/// receipts) while preserving shop information and app settings.
class AppReset {
  AppReset._();

  /// Erase business data and receipt drafts; keep shop row and settings prefs.
  static Future<void> wipeAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Forget pairing keys + paired devices first, so nothing erased below
    // is ever sent to another device.
    await forgetSyncForErase();
    final docs = await getApplicationDocumentsDirectory();
    final tmp = await getTemporaryDirectory();
    // Twice: a query still finishing on the old screen could rewrite data
    // (or a pref write land) right after the first pass.
    for (var pass = 0; pass < 2; pass++) {
      final db = await AppDatabase.instance.database;
      await wipe(
        db: db,
        docs: docs,
        temp: tmp,
        prefs: prefs,
      );
      if (pass == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    PrintService.clearCaches();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  /// Deletes business tables (not [shop_settings]), then clears photos,
  /// temp exports, and the receipt-edit draft pref.
  @visibleForTesting
  static Future<void> wipe({
    required Database db,
    required Directory docs,
    required Directory temp,
    required SharedPreferences prefs,
  }) async {
    await eraseBusinessTables(db);
    await wipeArtifacts(docs: docs, temp: temp, prefs: prefs);
  }

  /// Clears sale/customer/item tables; leaves [shop_settings] untouched.
  @visibleForTesting
  static Future<void> eraseBusinessTables(Database db) async {
    await db.transaction((txn) async {
      await txn.delete('sale_lines');
      await txn.delete('sales');
      await txn.delete('inventory_items');
      await txn.delete('categories');
      await txn.delete('customers');
    });
  }

  /// Clears item/customer photos and temp exports; removes receipt-edit
  /// draft pref only. Does not delete the DB file or settings prefs.
  @visibleForTesting
  static Future<void> wipeArtifacts({
    required Directory docs,
    required Directory temp,
    required SharedPreferences prefs,
  }) async {
    await _clearDirectoryContents(
      Directory(p.join(docs.path, LocalImageStore.folder)),
    );
    await _clearDirectoryContents(temp);
    // Receipt-edit draft only — do not clear locale / theme / PIN / setup.
    await prefs.remove(ResaleDraftNotifier.prefKey);
  }

  static Future<void> _clearDirectoryContents(Directory dir) async {
    if (!await dir.exists()) return;
    final entries = await dir.list(followLinks: false).toList();
    for (final e in entries) {
      try {
        await e.delete(recursive: true);
      } catch (err) {
        debugPrint('Reset: could not delete: $err');
      }
    }
  }
}

/// Root of the app. Reset App remounts the widget tree after erasure so
/// providers reload with empty business data and preserved settings.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  /// Erase authorized business data and remount the app.
  static Future<void> resetApp(BuildContext context) async {
    await context.findAncestorStateOfType<_AppRootState>()?._reset();
  }

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  Key _key = UniqueKey();
  bool _wiping = false;

  Future<void> _reset() async {
    if (_wiping) return;
    setState(() => _wiping = true);
    // Let the old app (and its providers) dispose before deleting data.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await AppReset.wipeAll();
    } catch (e) {
      debugPrint('Reset failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _key = UniqueKey();
      _wiping = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_wiping) {
      // Splash brand color while storage is wiped (well under a second).
      return const ColoredBox(color: Color(0xFF003362));
    }
    return ProviderScope(key: _key, child: const InventoryApp());
  }
}
