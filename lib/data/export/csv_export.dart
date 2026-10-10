import 'package:flutter/widgets.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// One professional CSV file with summary + sold items + sale lines.
class CsvExportService {
  Future<void> exportTurnover({
    BuildContext? context,
    required List<SoldItemAgg> items,
    required List<Sale> sales,
    required String currency,
    String? companyName,
    DateTime? from,
    DateTime? to,

    /// App translations for the report labels (English when omitted).
    String Function(String key)? t,
  }) async {
    String L(String key, String fallback) {
      final v = t?.call(key);
      return (v == null || v.isEmpty || v == key) ? fallback : v;
    }

    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final dir = await getTemporaryDirectory();
    final buf = StringBuffer();

    String money(num v) => v.toStringAsFixed(2);
    String d(DateTime v) => DateFormat('yyyy-MM-dd HH:mm').format(v.toLocal());
    String rangeLabel() {
      if (from == null && to == null) return L('csv_all_time', 'All time');
      final a = from == null ? '…' : DateFormat('yyyy-MM-dd').format(from);
      final b = to == null ? '…' : DateFormat('yyyy-MM-dd').format(to);
      return '$a ${L('csv_to', 'to')} $b';
    }

    final totalRevenue = sales.fold<double>(0, (s, e) => s + e.total);
    final totalQty = items.fold<double>(0, (s, e) => s + e.quantity);

    // —— Report header ——
    buf.writeln(_row([L('csv_turnover_export', 'Turnover Export')]));
    if (companyName != null && companyName.trim().isNotEmpty) {
      buf.writeln(_row([L('csv_company', 'Company'), companyName.trim()]));
    }
    buf.writeln(_row([L('csv_currency', 'Currency'), currency]));
    buf.writeln(_row([L('csv_period', 'Period'), rangeLabel()]));
    buf.writeln(_row([L('csv_exported_at', 'Exported at'), d(now)]));
    buf.writeln(_row([L('csv_sales_count', 'Sales count'), '${sales.length}']));
    buf.writeln(
      _row([L('csv_items_sold', 'Items sold (lines)'), formatQty(totalQty)]),
    );
    buf.writeln(
      _row([L('csv_total_revenue', 'Total revenue'), money(totalRevenue)]),
    );
    buf.writeln();

    // —— Sold items (aggregated) ——
    buf.writeln(_row([L('csv_sold_items', 'SOLD ITEMS')]));
    buf.writeln(
      _row([
        L('csv_item', 'Item'),
        L('csv_quantity', 'Quantity'),
        L('csv_unit', 'Unit'),
        '${L('csv_unit_price', 'Unit price')} ($currency)',
        '${L('csv_revenue', 'Revenue')} ($currency)',
      ]),
    );
    if (items.isEmpty) {
      buf.writeln(_row([L('csv_no_items', '(no items in this period)')]));
    } else {
      for (final i in items) {
        buf.writeln(
          _row([
            i.title,
            formatQty(i.quantity),
            i.unit ?? '',
            money(i.unitPrice),
            money(i.revenue),
          ]),
        );
      }
    }
    buf.writeln();

    // —— Sale line detail ——
    buf.writeln(_row([L('csv_sale_details', 'SALE DETAILS')]));
    buf.writeln(
      _row([
        L('csv_sale_id', 'Sale ID'),
        L('csv_date', 'Date'),
        L('csv_customer', 'Customer'),
        L('csv_item', 'Item'),
        L('csv_quantity', 'Quantity'),
        L('csv_unit', 'Unit'),
        '${L('csv_unit_price', 'Unit price')} ($currency)',
        '${L('csv_line_total', 'Line total')} ($currency)',
        '${L('csv_sale_total', 'Sale total')} ($currency)',
      ]),
    );
    if (sales.isEmpty) {
      buf.writeln(_row([L('csv_no_sales', '(no sales in this period)')]));
    } else {
      final ordered = [...sales]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final s in ordered) {
        final saleId = s.id.length >= 8
            ? s.id.substring(0, 8).toUpperCase()
            : s.id.toUpperCase();
        if (s.lines.isEmpty) {
          buf.writeln(
            _row([
              saleId,
              d(s.createdAt),
              (s.customerName == null || s.customerName == 'Guest')
                  ? L('guest', 'Guest')
                  : s.customerName!,
              '',
              '',
              '',
              '',
              '',
              money(s.total),
            ]),
          );
          continue;
        }
        for (final l in s.lines) {
          buf.writeln(
            _row([
              saleId,
              d(s.createdAt),
              (s.customerName == null || s.customerName == 'Guest')
                  ? L('guest', 'Guest')
                  : s.customerName!,
              l.title,
              formatQty(l.quantity),
              l.unit ?? '',
              money(l.unitPrice),
              money(l.lineTotal),
              money(s.total),
            ]),
          );
        }
      }
    }

    final file = File(p.join(dir.path, 'turnover_$stamp.csv'));
    await file.writeAsString(buf.toString(), flush: true);

    await shareWithOrigin(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject:
            '${L('csv_turnover_export', L('csv_turnover_export', 'Turnover Export'))} $stamp',
      ),
      (context != null && context.mounted) ? context : null,
    );
  }

  Future<void> exportReceipts({
    BuildContext? context,
    required List<Sale> sales,
    required String currency,
    String? companyName,
    DateTime? from,
    DateTime? to,

    /// App translations for the report labels (English when omitted).
    String Function(String key)? t,
  }) async {
    String L(String key, String fallback) {
      final v = t?.call(key);
      return (v == null || v.isEmpty || v == key) ? fallback : v;
    }

    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final dir = await getTemporaryDirectory();
    final buf = StringBuffer();

    String money(num v) => v.toStringAsFixed(2);
    String d(DateTime v) => DateFormat('yyyy-MM-dd HH:mm').format(v.toLocal());
    String rangeLabel() {
      if (from == null && to == null) return L('csv_all_time', 'All time');
      final a = from == null ? '…' : DateFormat('yyyy-MM-dd').format(from);
      final b = to == null ? '…' : DateFormat('yyyy-MM-dd').format(to);
      return '$a ${L('csv_to', 'to')} $b';
    }

    final totalRevenue = sales.fold<double>(0, (s, e) => s + e.total);

    buf.writeln(_row([L('csv_receipts_export', 'Receipts Export')]));
    if (companyName != null && companyName.trim().isNotEmpty) {
      buf.writeln(_row([L('csv_company', 'Company'), companyName.trim()]));
    }
    buf.writeln(_row([L('csv_currency', 'Currency'), currency]));
    buf.writeln(_row([L('csv_period', 'Period'), rangeLabel()]));
    buf.writeln(_row([L('csv_exported_at', 'Exported at'), d(now)]));
    buf.writeln(
      _row([L('csv_receipts_count', 'Receipts count'), '${sales.length}']),
    );
    buf.writeln(
      _row([L('csv_total_revenue', 'Total revenue'), money(totalRevenue)]),
    );
    buf.writeln();

    buf.writeln(_row([L('csv_receipts', 'RECEIPTS')]));
    buf.writeln(
      _row([
        L('csv_sale_id', 'Sale ID'),
        L('csv_date', 'Date'),
        L('csv_customer', 'Customer'),
        L('csv_item', 'Item'),
        L('csv_quantity', 'Quantity'),
        L('csv_unit', 'Unit'),
        '${L('csv_unit_price', 'Unit price')} ($currency)',
        '${L('csv_line_total', 'Line total')} ($currency)',
        '${L('csv_sale_total', 'Sale total')} ($currency)',
      ]),
    );

    if (sales.isEmpty) {
      buf.writeln(_row([L('csv_no_receipts', '(no receipts in this period)')]));
    } else {
      final sorted = [...sales]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final s in sorted) {
        final saleId = s.id.length >= 8
            ? s.id.substring(0, 8).toUpperCase()
            : s.id.toUpperCase();
        if (s.lines.isEmpty) {
          buf.writeln(
            _row([
              saleId,
              d(s.createdAt),
              (s.customerName == null || s.customerName == 'Guest')
                  ? L('guest', 'Guest')
                  : s.customerName!,
              '',
              '',
              '',
              '',
              '',
              money(s.total),
            ]),
          );
          continue;
        }
        for (final l in s.lines) {
          buf.writeln(
            _row([
              saleId,
              d(s.createdAt),
              (s.customerName == null || s.customerName == 'Guest')
                  ? L('guest', 'Guest')
                  : s.customerName!,
              l.title,
              formatQty(l.quantity),
              l.unit ?? '',
              money(l.unitPrice),
              money(l.lineTotal),
              money(s.total),
            ]),
          );
        }
      }
    }

    final file = File(p.join(dir.path, 'receipts_$stamp.csv'));
    await file.writeAsString(buf.toString(), flush: true);

    await shareWithOrigin(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject:
            '${L('csv_receipts_export', L('csv_receipts_export', 'Receipts Export'))} $stamp',
      ),
      (context != null && context.mounted) ? context : null,
    );
  }

  String _row(List<String> cells) => cells.map(_escape).join(',');

  String _escape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
