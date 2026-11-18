import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/data/export/xlsx_export.dart';
import 'package:inventory_app/domain/models/models.dart';

Sale _sale(String id, DateTime at, String? customer, List<SaleLine> lines) =>
    Sale(
      id: id,
      customerName: customer,
      total: lines.fold(0.0, (s, l) => s + l.lineTotal),
      createdAt: at,
      lines: lines,
    );

SaleLine _line(String title, double price, double qty, [String? unit]) =>
    SaleLine(
      itemId: title,
      title: title,
      unitPrice: price,
      quantity: qty,
      unit: unit,
    );

num _n(Data? c) => switch (c!.value) {
  DoubleCellValue(:final value) => value,
  IntCellValue(:final value) => value,
  final v => throw StateError('not numeric: $v'),
};

void main() {
  setUpAll(() async {
    for (final code in S.supported.keys) {
      await initializeDateFormatting(code);
    }
  });

  final sales = [
    _sale('bbbbbbbb-2', DateTime(2026, 10, 12, 9, 30), null, [
      _line('Cheese', 12.9, 2, 'kg'),
      _line('Bread', 3.5, 1),
    ]),
    _sale('aaaaaaaa-1', DateTime(2026, 9, 1, 14, 5), 'Anna', [
      _line('Milk', 1.25, 4, 'l'),
    ]),
  ];

  List<List<Data?>> rows(List<int> bytes) {
    final x = Excel.decodeBytes(bytes);
    return x.tables[x.tables.keys.first]!.rows;
  }

  test('one row per item sold, numeric cells, bold TOTAL row', () {
    final t = S('en');
    final bytes = TurnoverXlsxExport.build(
      sales: sales,
      companyName: 'Demo Shop',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 10, 19),
      currencySymbol: '€',
      locale: 'en',
      t: t.call,
    );
    final r = rows(bytes);
    expect(r[0][0]!.value.toString(), 'Demo Shop');
    expect(r[1][0]!.value.toString(), startsWith('Period: '));
    expect(r[3].map((c) => c?.value.toString()).toList(), [
      'Date',
      'Receipt No.',
      'Customer',
      'Item',
      'Quantity',
      'Price',
      'Total',
    ]);
    // Oldest first, one row per line.
    expect(r[4][1]!.value.toString(), 'AAAAAAAA');
    expect(r[4][2]!.value.toString(), 'Anna');
    expect(r[4][3]!.value.toString(), 'Milk');
    expect(r[4][0]!.value, isA<DateTimeCellValue>());
    expect(_n(r[4][4]), 4);
    expect(r[4][4]!.cellStyle!.numberFormat.formatCode, '0.##" l"');
    expect(_n(r[4][5]), 1.25);
    expect(_n(r[4][6]), 5.0);
    expect(r[5][2]!.value.toString(), 'Guest');
    expect(r[5][3]!.value.toString(), 'Cheese');
    expect(_n(r[5][6]), 25.8);
    expect(r[5][6]!.cellStyle!.numberFormat.formatCode, contains('€'));
    expect(r[6][3]!.value.toString(), 'Bread');
    // TOTAL = 5.00 + 25.80 + 3.50
    expect(r[7][0]!.value.toString(), 'TOTAL');
    expect(r[7][0]!.cellStyle!.isBold, isTrue);
    expect(_n(r[7][6]), 34.3);
    expect(r.length, 8);
  });

  test('period filter, empty period and file name', () {
    final inOct = TurnoverXlsxExport.inRange(
      sales,
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 31, 23, 59),
    );
    expect(inOct.map((s) => s.id), ['bbbbbbbb-2']);
    final bytes = TurnoverXlsxExport.build(
      sales: const [],
      companyName: 'X',
      from: DateTime(2026, 10, 5),
      to: DateTime(2026, 10, 19),
      currencySymbol: '€',
      locale: 'en',
      t: S('en').call,
    );
    final r = rows(bytes);
    expect(r.last[0]!.value.toString(), 'TOTAL');
    expect(_n(r.last[6]), 0);
    expect(
      TurnoverXlsxExport.fileName(DateTime(2026, 9, 1), DateTime(2026, 10, 19)),
      'Turnover_2026-09-01_2026-10-19.xlsx',
    );
    // All = from the first sale.
    expect(
      TurnoverXlsxExport.effectiveFrom(sales, null, DateTime(2026, 10, 19)),
      DateTime(2026, 9, 1, 14, 5),
    );
    final all = exportPeriodRange(ExportPeriod.all, DateTime(2026, 10, 19));
    expect(all.from, isNull);
    final w2 = exportPeriodRange(ExportPeriod.w2, DateTime(2026, 10, 19, 8));
    expect(w2.from, DateTime(2026, 10, 6));
  });

  test('column headers are translated in every language', () {
    const keys = [
      'xlsx_period',
      'xlsx_date',
      'xlsx_receipt_no',
      'xlsx_customer',
      'xlsx_item',
      'xlsx_quantity',
      'xlsx_price',
      'xlsx_total',
      'xlsx_total_row',
    ];
    for (final code in S.supported.keys) {
      for (final k in keys) {
        expect(S(code)(k), isNot(k), reason: '$code $k');
      }
    }
    final de = rows(
      TurnoverXlsxExport.build(
        sales: sales,
        companyName: 'Shop',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 10, 19),
        currencySymbol: '€',
        locale: 'de',
        t: S('de').call,
      ),
    );
    expect(de[3][1]!.value.toString(), 'Beleg-Nr.');
    expect(de[4][2]!.value.toString(), 'Anna');
    expect(de[5][2]!.value.toString(), 'Gast');
    expect(de.last[0]!.value.toString(), 'GESAMT');
  });
}
