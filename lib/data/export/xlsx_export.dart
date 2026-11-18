import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Periods offered by the export sheet (same options as Turnover).
enum ExportPeriod { w2, m1, m3, m6, y1, y2, all }

/// Translation keys of the period chips (shared with the Turnover page).
const exportPeriodLabelKeys = <ExportPeriod, String>{
  ExportPeriod.w2: 'range_2w',
  ExportPeriod.m1: 'range_1m',
  ExportPeriod.m3: 'range_3m',
  ExportPeriod.m6: 'range_6m',
  ExportPeriod.y1: 'range_1y',
  ExportPeriod.y2: 'range_2y',
  ExportPeriod.all: 'range_all',
};

/// Start / end of [period] counted back from [now] (same day spans as the
/// Turnover chips). `All` has no start.
({DateTime? from, DateTime to}) exportPeriodRange(
  ExportPeriod period,
  DateTime now,
) {
  final to = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  DateTime back(int days) {
    final d = now.subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day);
  }

  return switch (period) {
    ExportPeriod.w2 => (from: back(13), to: to),
    ExportPeriod.m1 => (from: back(30), to: to),
    ExportPeriod.m3 => (from: back(90), to: to),
    ExportPeriod.m6 => (from: back(180), to: to),
    ExportPeriod.y1 => (from: back(365), to: to),
    ExportPeriod.y2 => (from: back(730), to: to),
    ExportPeriod.all => (from: null, to: to),
  };
}

/// The single turnover export: a real .xlsx with one row per item sold.
class TurnoverXlsxExport {
  TurnoverXlsxExport._();

  static final _day = DateFormat('yyyy-MM-dd');

  /// Sales of [sales] inside [from]..[to] (null = open end).
  static List<Sale> inRange(List<Sale> sales, DateTime? from, DateTime? to) {
    final out = sales.where((s) {
      if (from != null && s.createdAt.isBefore(from)) return false;
      if (to != null && s.createdAt.isAfter(to)) return false;
      return true;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  /// Actual first day of the file: [from], or the first sale for `All`.
  static DateTime effectiveFrom(List<Sale> sales, DateTime? from, DateTime to) {
    if (from != null) return from;
    if (sales.isEmpty) return to;
    return sales
        .map((s) => s.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  static String fileName(DateTime from, DateTime to) =>
      'Turnover_${_day.format(from)}_${_day.format(to)}.xlsx';

  /// Builds the workbook bytes. Numbers are numeric cells; the currency
  /// symbol and unit are shown through the cell number format (the decimal /
  /// thousands separators then follow the spreadsheet app's locale, which
  /// is how numeric .xlsx cells work).
  static List<int> build({
    required List<Sale> sales,
    required String companyName,
    required DateTime from,
    required DateTime to,
    required String currencySymbol,
    required String locale,
    required String Function(String key) t,
  }) {
    String L(String key, String fallback) {
      final v = t(key);
      return (v.isEmpty || v == key) ? fallback : v;
    }

    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final name = _sheetName(L('turnover', 'Turnover'));
    if (name != defaultSheet) excel.rename(defaultSheet, name);
    final sheet = excel[name];

    final symbol = currencySymbol.replaceAll('"', '').trim();
    final moneyFmt = CustomNumericNumFormat(
      formatCode: symbol.isEmpty ? '#,##0.00' : '#,##0.00 "$symbol"',
    );
    final dateFmt = CustomDateTimeNumFormat(formatCode: 'dd.mm.yyyy hh:mm');
    final bold = CellStyle(bold: true);
    final title = CellStyle(bold: true, fontSize: 14);

    void put(int row, int col, CellValue? v, [CellStyle? style]) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        v,
        cellStyle: style,
      );
    }

    // Header block: company + period.
    put(0, 0, TextCellValue(companyName.trim()), title);
    put(
      1,
      0,
      TextCellValue(
        '${L('xlsx_period', 'Period')}: '
        '${formatDateShort(from, locale)} – ${formatDateShort(to, locale)}',
      ),
    );

    const headerRow = 3;
    final headers = [
      L('xlsx_date', 'Date'),
      L('xlsx_receipt_no', 'Receipt No.'),
      L('xlsx_customer', 'Customer'),
      L('xlsx_item', 'Item'),
      L('xlsx_quantity', 'Quantity'),
      L('xlsx_price', 'Price'),
      L('xlsx_total', 'Total'),
    ];
    for (var c = 0; c < headers.length; c++) {
      put(headerRow, c, TextCellValue(headers[c]), bold);
    }

    var row = headerRow + 1;
    var sum = 0.0;
    for (final s in inRange(sales, null, null)) {
      final d = s.createdAt;
      final receiptNo = (s.id.length > 8 ? s.id.substring(0, 8) : s.id)
          .toUpperCase();
      final customer =
          (s.customerName == null ||
              s.customerName!.trim().isEmpty ||
              s.customerName == 'Guest')
          ? L('guest', 'Guest')
          : s.customerName!;
      for (final l in s.lines) {
        final unit = (l.unit ?? '').replaceAll('"', '').trim();
        // Use a real numeric format (not General+"text") so Excel/Sheets
        // do not render the cell as #######.
        final qtyFmt = CustomNumericNumFormat(
          formatCode: unit.isEmpty ? '0.##' : '0.##" $unit"',
        );
        put(
          row,
          0,
          DateTimeCellValue(
            year: d.year,
            month: d.month,
            day: d.day,
            hour: d.hour,
            minute: d.minute,
          ),
          CellStyle(numberFormat: dateFmt),
        );
        put(row, 1, TextCellValue(receiptNo));
        put(row, 2, TextCellValue(customer));
        put(row, 3, TextCellValue(l.title));
        put(
          row,
          4,
          DoubleCellValue(l.quantity),
          CellStyle(numberFormat: qtyFmt),
        );
        put(
          row,
          5,
          DoubleCellValue(_round2(l.unitPrice)),
          CellStyle(numberFormat: moneyFmt),
        );
        put(
          row,
          6,
          DoubleCellValue(_round2(l.lineTotal)),
          CellStyle(numberFormat: moneyFmt),
        );
        sum += l.lineTotal;
        row++;
      }
    }

    put(row, 0, TextCellValue(L('xlsx_total_row', 'TOTAL')), bold);
    put(
      row,
      6,
      DoubleCellValue(_round2(sum)),
      CellStyle(bold: true, numberFormat: moneyFmt),
    );

    // Wide enough for date/time and money+currency so apps do not show ####.
    const widths = [20.0, 14.0, 20.0, 32.0, 16.0, 18.0, 18.0];
    for (var c = 0; c < widths.length; c++) {
      sheet.setColumnWidth(c, widths[c]);
    }
    return excel.encode()!;
  }

  /// Writes the file for [period] and opens the system share sheet.
  static Future<void> exportAndShare({
    BuildContext? context,
    required List<Sale> allSales,
    required DateTime? from,
    required DateTime to,
    required String companyName,
    required String currencySymbol,
    required String locale,
    required String Function(String key) t,
  }) async {
    final sales = inRange(allSales, from, to);
    final start = effectiveFrom(sales, from, to);
    final bytes = build(
      sales: sales,
      companyName: companyName,
      from: start,
      to: to,
      currencySymbol: currencySymbol,
      locale: locale,
      t: t,
    );
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName(start, to)));
    await file.writeAsBytes(bytes, flush: true);
    await shareWithOrigin(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: p.basenameWithoutExtension(file.path),
      ),
      (context != null && context.mounted) ? context : null,
    );
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static String _sheetName(String raw) {
    final clean = raw.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), '').trim();
    if (clean.isEmpty) return 'Turnover';
    return clean.length > 31 ? clean.substring(0, 31) : clean;
  }
}
