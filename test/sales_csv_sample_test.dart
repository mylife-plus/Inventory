import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/data/export/sales_csv_export.dart';
import 'package:inventory_app/domain/models/models.dart';

/// Nov 16 client review: a receipt with 7 items must be 7 item rows.
/// `SAMPLE_CSV_DIR=/some/dir flutter test <this file>` also writes the
/// files for inspection (sample.csv = German settings, ; and decimal comma).
void main() {
  final lines = [
    const SaleLine(itemId: '1', title: 'Brot', unitPrice: 2.5, quantity: 2),
    const SaleLine(itemId: '2', title: 'Milch 1 L', unitPrice: 1.19, quantity: 1),
    const SaleLine(itemId: '3', title: 'Käse "alt"', unitPrice: 12.9, quantity: 0.5, unit: 'kg'),
    const SaleLine(itemId: '4', title: 'Äpfel; rot', unitPrice: 3.2, quantity: 1, unit: 'kg'),
    const SaleLine(itemId: '5', title: 'Kaffee, Espresso', unitPrice: 8.99, quantity: 1),
    const SaleLine(itemId: '6', title: 'Butter', unitPrice: 2.29, quantity: 3),
    const SaleLine(itemId: '7', title: 'Eier (10 Stk.)', unitPrice: 3.49, quantity: 1),
  ];
  final sale = Sale(
    id: '7a3f9c21-0000',
    customerName: 'Jürgen Müller',
    total: lines.fold(0.0, (s, l) => s + l.lineTotal),
    createdAt: DateTime(2026, 11, 15, 19, 28),
    lines: lines,
  );

  for (final (lang, sep, name) in [
    ('de', ',', 'sample.csv'),
    ('en', '.', 'sample_en.csv'),
  ]) {
    test('7-item receipt → 7 item rows ($lang)', () async {
      final csv = SalesCsvExport.receipts(
        sales: [sale],
        decimalSeparator: sep,
        currencySymbol: '€',
        t: S(lang).call,
      );
      final rows = csv.substring(1).split('\r\n')..removeLast();
      expect(rows.length, 1 + 7 + 1, reason: 'header + 7 items + total');
      final d = SalesCsvExport.delimiterFor(sep);
      for (var i = 1; i <= 7; i++) {
        expect(rows[i].startsWith('15.11.2026${d}19:28${d}7A3F9C21$d'), isTrue,
            reason: 'row $i repeats date and receipt no.');
        expect(rows[i].contains('$d$i$d'), isTrue, reason: 'position $i');
      }
      expect(rows[1].contains('Brot'), isTrue);
      expect(rows[7].contains('Eier (10 Stk.)'), isTrue);
      final dir = Platform.environment['SAMPLE_CSV_DIR'];
      if (dir != null) {
        await File('$dir/$name').writeAsBytes(utf8.encode(csv), flush: true);
      }
    });
  }
}
