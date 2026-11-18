import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:inventory_app/data/export/sales_csv_export.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Nov 14 client review: "export receipt as csv only shows one item".
/// The whole real path: sell 20 items in one receipt into the database,
/// read the receipts back like the Receipts page does, export → every item
/// is a row (and the Turnover export too).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    docs = await Directory.systemTemp.createTemp('csv_db_docs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => docs.path,
    );
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
    await docs.delete(recursive: true);
  });

  test('20-item receipt → 20 rows in the receipts CSV and in turnover',
      () async {
    final db = AppDatabase.instance;
    final inventory = InventoryRepository(db);
    final sales = SaleRepository(db);
    final now = DateTime(2026, 11, 14, 10, 30);
    final lines = <SaleLine>[];
    for (var i = 1; i <= 20; i++) {
      await inventory.upsertItem(InventoryItem(
        id: 'item$i',
        title: 'Item $i',
        price: i.toDouble(),
        amount: 50,
        createdAt: now,
        updatedAt: now,
      ));
      lines.add(SaleLine(
        itemId: 'item$i',
        title: 'Item $i',
        unitPrice: i.toDouble(),
        quantity: 2,
      ));
    }
    await sales.createSale(lines: lines, createdAt: now);
    // A second, one-item receipt so receipts don't run together.
    await sales.createSale(lines: [
      const SaleLine(itemId: 'item1', title: 'Item 1', unitPrice: 1, quantity: 1),
    ], createdAt: now.add(const Duration(minutes: 5)));

    final all = await sales.list();
    expect(all.length, 2);
    expect(all.last.lines.length, 20, reason: 'all lines read back');

    final t = S('en');
    final csv = SalesCsvExport.receipts(
      sales: SalesCsvExport.inRange(all, now, now),
      decimalSeparator: '.',
      currencySymbol: '€',
      t: t.call,
    );
    final rows = csv.substring(1).split('\r\n')..removeLast();
    // Header + 20 items + 1 item + TOTAL.
    expect(rows.length, 1 + 20 + 1 + 1);
    for (var i = 1; i <= 20; i++) {
      expect(rows.where((r) => r.contains(',$i,Item $i,2,')).length, 1,
          reason: 'Item $i has its own row');
    }
    expect(rows[1].endsWith(',1.00,2.00,420.00'), isTrue,
        reason: 'price, line total, receipt total');
    expect(rows[2].endsWith(',2.00,4.00,'), isTrue, reason: 'total once');
    expect(rows.last, 'TOTAL,,,,,,,,,,421.00');

    final turnover = SalesCsvExport.turnover(
      sales: SalesCsvExport.inRange(all, now, now),
      decimalSeparator: ',',
      currencySymbol: '€',
      t: t.call,
    );
    final tRows = turnover.substring(1).split('\r\n')..removeLast();
    expect(tRows.length, 1 + 21 + 1);
    expect(tRows.last, 'TOTAL;;;;;;;;421,00');
  });
}
