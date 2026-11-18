import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/data/export/sales_csv_export.dart';
import 'package:inventory_app/domain/models/models.dart';

Sale _sale(String id, DateTime at, List<SaleLine> lines, {String? customer}) =>
    Sale(
      id: id,
      customerName: customer,
      total: lines.fold(0.0, (s, l) => s + l.lineTotal),
      createdAt: at,
      lines: lines,
    );

final _sales = [
  _sale('bbbbbbbb-2', DateTime(2026, 10, 20, 17, 5), const [
    SaleLine(itemId: 'k', title: 'Käse "alt"; würzig', unitPrice: 12.9,
        quantity: 0.5, unit: 'kg'),
  ], customer: 'Jürgen Müller'),
  _sale('aaaaaaaa-1', DateTime(2026, 10, 1, 9, 30), const [
    SaleLine(itemId: 'b', title: 'Brot', unitPrice: 2.5, quantity: 2),
    SaleLine(itemId: 'f', title: '=HYPERLINK("x")', unitPrice: 1, quantity: 1),
  ]),
];

/// Cells in one CSV row split on [d] (quoted delimiters don't count).
int _cells(String row, [String d = ',']) {
  var n = 1;
  var q = false;
  for (final ch in row.split('')) {
    if (ch == '"') q = !q;
    if (!q && ch == d) n++;
  }
  return n;
}

void main() {
  final de = S('de');
  final en = S('en');

  test('turnover CSV: BOM, ; with decimal comma, quoting, formula guard', () {
    final csv = SalesCsvExport.turnover(
      sales: _sales,
      decimalSeparator: ',',
      currencySymbol: '€',
      t: de.call,
    );
    expect(csv.startsWith('\uFEFF'), isTrue);
    final rows = csv.substring(1).split('\r\n')..removeLast();
    expect(rows.first,
        'Datum;Uhrzeit;Beleg-Nr.;Kunde;Artikel;Menge;Einheit;Preis (€);Gesamt (€)');
    // Oldest first, one row per line.
    expect(rows[1], '01.10.2026;09:30;AAAAAAAA;Gast;Brot;2;;2,50;5,00');
    expect(rows[2],
        '01.10.2026;09:30;AAAAAAAA;Gast;"\'=HYPERLINK(""x"")";1;;1,00;1,00');
    expect(rows[3],
        '20.10.2026;17:05;BBBBBBBB;Jürgen Müller;"Käse ""alt""; würzig";0,5;kg;12,90;6,45');
    expect(rows.last, 'GESAMT;;;;;;;;12,45');
    // UTF-8 bytes: EF BB BF then ü as C3 BC.
    final bytes = utf8.encode(csv);
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes).contains('Müller'), isTrue);
  });

  test('receipts CSV: one complete row per item, , with decimal point', () {
    final csv = SalesCsvExport.receipts(
      sales: _sales,
      decimalSeparator: '.',
      currencySymbol: r'$',
      t: en.call,
    );
    final rows = csv.substring(1).split('\r\n')..removeLast();
    expect(rows.first,
        r'Date,Time,Receipt No.,Customer,Pos.,Item,Quantity,Unit,'
        r'Unit price ($),Line total ($),Receipt total ($)');
    // Every row has its item, qty, price and line total; the receipt total
    // only on the receipt's first row.
    expect(rows[1], '01.10.2026,09:30,AAAAAAAA,Guest,1,Brot,2,,2.50,5.00,6.00');
    expect(rows[2],
        '01.10.2026,09:30,AAAAAAAA,Guest,2,"\'=HYPERLINK(""x"")",1,,1.00,1.00,');
    expect(rows[3],
        '20.10.2026,17:05,BBBBBBBB,Jürgen Müller,1,"Käse ""alt""; würzig",'
        '0.5,kg,12.90,6.45,6.45');
    expect(rows.last, 'TOTAL,,,,,,,,,,12.45');
    expect(rows.length, 5);
    // Same number of cells on every row (no viewer can shift columns).
    final counts = rows.map((r) => _cells(r)).toSet();
    expect(counts, {11});
  });

  test('receipts CSV: a 20-item receipt is 20 full rows, every cell short',
      () {
    final big = _sale('cccccccc-3', DateTime(2026, 11, 11, 9), [
      for (var i = 1; i <= 20; i++)
        SaleLine(itemId: 'i$i', title: 'Brot $i', unitPrice: 2.5, quantity: 1),
    ]);
    final csv = SalesCsvExport.receipts(
      sales: [..._sales, big],
      decimalSeparator: ',',
      currencySymbol: '€',
      t: de.call,
    );
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv.contains('\n') && !csv.replaceAll('\r\n', '').contains('\n'),
        isTrue, reason: 'CRLF only, no stray line breaks');
    final rows = csv.substring(1).split('\r\n')..removeLast();
    final bigRows = rows.where((r) => r.contains('CCCCCCCC')).toList();
    expect(bigRows.length, 20);
    expect(bigRows.first,
        '11.11.2026;09:00;CCCCCCCC;Gast;1;Brot 1;1;;2,50;2,50;50,00');
    expect(bigRows.last,
        '11.11.2026;09:00;CCCCCCCC;Gast;20;Brot 20;1;;2,50;2,50;');
    final longest = rows
        .expand((r) => r.split(';'))
        .fold<int>(0, (m, c) => c.length > m ? c.length : m);
    expect(longest, lessThan(40));
    expect(rows.last, 'GESAMT;;;;;;;;;;62,45');
  });

  test('receipts CSV header in every language has the item columns', () {
    for (final code in S.supported.keys) {
      final t = S(code);
      for (final k in ['csv_pos', 'csv_receipt_total', 'csv_line_total',
          'csv_unit_price', 'xlsx_item']) {
        expect(t(k), isNot(k), reason: '$code: $k');
      }
    }
  });

  test('range is inclusive of the whole To day', () {
    final inOct1 = SalesCsvExport.inRange(
        _sales, DateTime(2026, 10, 1, 15), DateTime(2026, 10, 1));
    expect(inOct1.map((s) => s.id), ['aaaaaaaa-1']);
    final toOct20 = SalesCsvExport.inRange(
        _sales, DateTime(2026, 10, 2), DateTime(2026, 10, 20));
    expect(toOct20.map((s) => s.id), ['bbbbbbbb-2']);
    expect(SalesCsvExport.inRange(_sales, null, null).length, 2);
  });

  test('empty range still gives a valid file (header + total)', () {
    final csv = SalesCsvExport.turnover(
      sales: const [],
      decimalSeparator: ',',
      currencySymbol: '€',
      t: en.call,
    );
    final rows = csv.substring(1).split('\r\n')..removeLast();
    expect(rows.length, 2);
    expect(rows.last, 'TOTAL;;;;;;;;0,00');
  });

  test('cell escaping rules', () {
    expect(SalesCsvExport.cell('plain', ';'), 'plain');
    expect(SalesCsvExport.cell('a;b', ';'), '"a;b"');
    expect(SalesCsvExport.cell('a,b', ';'), 'a,b');
    expect(SalesCsvExport.cell('line\nbreak', ','), '"line\nbreak"');
    expect(SalesCsvExport.cell('-5', ',', text: false), '-5');
    expect(SalesCsvExport.cell('-x', ','), "'-x");
    expect(SalesCsvExport.cell('@cmd', ','), "'@cmd");
  });

  test('file name', () {
    expect(
      SalesCsvExport.fileName('Receipts', DateTime(2026, 9, 1),
          DateTime(2026, 10, 19)),
      'Receipts_2026-09-01_2026-10-19.csv',
    );
  });
}
