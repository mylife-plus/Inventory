import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:inventory_app/core/utils/date_bounds.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// CSV exports of Settings → Receipts and Settings → Export Turnover.
///
/// * UTF-8 with BOM so Excel shows umlauts / accents correctly.
/// * Delimiter follows the app's decimal separator: `;` with a decimal comma
///   (what Excel expects in DE/FR/ES/PT), `,` with a decimal point.
/// * Numbers use the app's decimal separator, no thousands grouping, no
///   currency symbol inside cells (the symbol is in the column header), so
///   spreadsheets read them as numbers.
/// * Dates `dd.MM.yyyy` (as in the app's date fields) + a separate time
///   column `HH:mm`.
/// * RFC 4180 quoting; text that would start a formula (= + - @) is
///   prefixed with ' so spreadsheets never execute it.
class SalesCsvExport {
  SalesCsvExport._();

  static const bom = '\uFEFF';
  static const eol = '\r\n';
  static final _day = DateFormat('dd.MM.yyyy');
  static final _time = DateFormat('HH:mm');
  static final _fileDay = DateFormat('yyyy-MM-dd');

  static String delimiterFor(String decimalSeparator) =>
      decimalSeparator == ',' ? ';' : ',';

  /// One CSV cell. [text] cells get the formula guard; numbers do not.
  static String cell(String value, String delimiter, {bool text = true}) {
    var v = value;
    if (text && v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
    final needsQuotes =
        v.contains(delimiter) ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r') ||
        v.startsWith(' ') ||
        v.endsWith(' ');
    if (!needsQuotes) return v;
    return '"${v.replaceAll('"', '""')}"';
  }

  static String number(double v, String decimalSeparator, {int decimals = 2}) {
    final s = v.toStringAsFixed(decimals);
    return decimalSeparator == ',' ? s.replaceAll('.', ',') : s;
  }

  /// Quantity without trailing zeros (2, 1.5, 0.25).
  static String qty(double v, String decimalSeparator) {
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return decimalSeparator == ',' ? s.replaceAll('.', ',') : s;
  }

  static String receiptNo(Sale s) =>
      (s.id.length > 8 ? s.id.substring(0, 8) : s.id).toUpperCase();

  /// Sales with [from] day ≤ createdAt ≤ end of [to] day, oldest first.
  static List<Sale> inRange(List<Sale> sales, DateTime? from, DateTime? to) {
    final start = from == null ? null : dayOf(from);
    final end = to == null ? null : endOfDay(to);
    return sales.where((s) {
      if (start != null && s.createdAt.isBefore(start)) return false;
      if (end != null && s.createdAt.isAfter(end)) return false;
      return true;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static String _customer(Sale s, String guest) {
    final n = s.customerName?.trim() ?? '';
    return (n.isEmpty || n == 'Guest') ? guest : n;
  }

  static String _money(String label, String symbol) {
    final sym = symbol.trim();
    return sym.isEmpty ? label : '$label ($sym)';
  }

  static String _row(List<String> cells) => cells.join() + eol;

  /// Turnover: one row per item sold + a TOTAL row.
  static String turnover({
    required List<Sale> sales,
    required String decimalSeparator,
    required String currencySymbol,
    required String Function(String key) t,
  }) {
    final d = delimiterFor(decimalSeparator);
    String c(String v, {bool text = true}) => cell(v, d, text: text);
    String line(List<String> cells) => _row([cells.join(d)]);
    final b = StringBuffer(bom)
      ..write(
        line([
          c(t('xlsx_date')),
          c(t('csv_time')),
          c(t('xlsx_receipt_no')),
          c(t('xlsx_customer')),
          c(t('xlsx_item')),
          c(t('xlsx_quantity')),
          c(t('csv_unit')),
          c(_money(t('xlsx_price'), currencySymbol)),
          c(_money(t('xlsx_total'), currencySymbol)),
        ]),
      );
    var sum = 0.0;
    for (final s in inRange(sales, null, null)) {
      for (final l in s.lines) {
        sum += l.lineTotal;
        b.write(
          line([
            c(_day.format(s.createdAt)),
            c(_time.format(s.createdAt)),
            c(receiptNo(s)),
            c(_customer(s, t('guest'))),
            c(l.title),
            c(qty(l.quantity, decimalSeparator), text: false),
            c(l.unit?.trim() ?? ''),
            c(number(l.unitPrice, decimalSeparator), text: false),
            c(number(l.lineTotal, decimalSeparator), text: false),
          ]),
        );
      }
    }
    b.write(
      line([
        c(t('xlsx_total_row')),
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        c(number(sum, decimalSeparator), text: false),
      ]),
    );
    return b.toString();
  }

  /// Receipts: one complete row per sold item + a TOTAL row.
  ///
  /// Every row stands on its own: date, time, receipt no. and customer, then
  /// the item's position in the receipt (1, 2, 3 …), name, quantity, unit,
  /// unit price and line total. A receipt with 7 items is 7 filled rows, so
  /// no viewer (iPhone preview, Numbers, Excel, Android) can make it look
  /// like one item. The receipt total sits only on the receipt's first row
  /// so the column still sums correctly. Short cells only: a long joined
  /// cell made the iPhone preview zoom out (Nov 12).
  static String receipts({
    required List<Sale> sales,
    required String decimalSeparator,
    required String currencySymbol,
    required String Function(String key) t,
  }) {
    final d = delimiterFor(decimalSeparator);
    String c(String v, {bool text = true}) => cell(v, d, text: text);
    String n(double v) => c(number(v, decimalSeparator), text: false);
    String line(List<String> cells) => _row([cells.join(d)]);
    final b = StringBuffer(bom)
      ..write(
        line([
          c(t('xlsx_date')),
          c(t('csv_time')),
          c(t('xlsx_receipt_no')),
          c(t('xlsx_customer')),
          c(t('csv_pos')),
          c(t('xlsx_item')),
          c(t('xlsx_quantity')),
          c(t('csv_unit')),
          c(_money(t('csv_unit_price'), currencySymbol)),
          c(_money(t('csv_line_total'), currencySymbol)),
          c(_money(t('csv_receipt_total'), currencySymbol)),
        ]),
      );
    var sum = 0.0;
    for (final s in inRange(sales, null, null)) {
      sum += s.total;
      final head = [
        c(_day.format(s.createdAt)),
        c(_time.format(s.createdAt)),
        c(receiptNo(s)),
        c(_customer(s, t('guest'))),
      ];
      if (s.lines.isEmpty) {
        b.write(line([...head, '', '', '', '', '', '', n(s.total)]));
        continue;
      }
      for (var i = 0; i < s.lines.length; i++) {
        final l = s.lines[i];
        b.write(
          line([
            ...head,
            c('${i + 1}', text: false),
            c(l.title),
            c(qty(l.quantity, decimalSeparator), text: false),
            c(l.unit?.trim() ?? ''),
            n(l.unitPrice),
            n(l.lineTotal),
            i == 0 ? n(s.total) : '',
          ]),
        );
      }
    }
    b.write(
      line([c(t('xlsx_total_row')), '', '', '', '', '', '', '', '', '', n(sum)]),
    );
    return b.toString();
  }

  /// e.g. `Receipts_2026-09-01_2026-10-19.csv`.
  static String fileName(String prefix, DateTime from, DateTime to) {
    final clean = prefix.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${clean.isEmpty ? 'Export' : clean}_'
        '${_fileDay.format(from)}_${_fileDay.format(to)}.csv';
  }

  /// Writes [csv] (already BOM-prefixed) as UTF-8 into the temp folder.
  static Future<File> write(String name, String csv) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(utf8.encode(csv), flush: true);
    return file;
  }
}
