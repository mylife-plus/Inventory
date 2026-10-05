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
    required List<SoldItemAgg> items,
    required List<Sale> sales,
    required String currency,
    String? companyName,
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final dir = await getTemporaryDirectory();
    final buf = StringBuffer();

    String money(num v) => v.toStringAsFixed(2);
    String d(DateTime v) => DateFormat('yyyy-MM-dd HH:mm').format(v.toLocal());
    String rangeLabel() {
      if (from == null && to == null) return 'All time';
      final a = from == null ? '…' : DateFormat('yyyy-MM-dd').format(from);
      final b = to == null ? '…' : DateFormat('yyyy-MM-dd').format(to);
      return '$a to $b';
    }

    final totalRevenue = sales.fold<double>(0, (s, e) => s + e.total);
    final totalQty = items.fold<double>(0, (s, e) => s + e.quantity);

    // —— Report header ——
    buf.writeln(_row(['Turnover Export']));
    if (companyName != null && companyName.trim().isNotEmpty) {
      buf.writeln(_row(['Company', companyName.trim()]));
    }
    buf.writeln(_row(['Currency', currency]));
    buf.writeln(_row(['Period', rangeLabel()]));
    buf.writeln(_row(['Exported at', d(now)]));
    buf.writeln(_row(['Sales count', '${sales.length}']));
    buf.writeln(_row(['Items sold (lines)', formatQty(totalQty)]));
    buf.writeln(_row(['Total revenue', money(totalRevenue)]));
    buf.writeln();

    // —— Sold items (aggregated) ——
    buf.writeln(_row(['SOLD ITEMS']));
    buf.writeln(_row([
      'Item',
      'Quantity',
      'Unit',
      'Unit price ($currency)',
      'Revenue ($currency)',
    ]));
    if (items.isEmpty) {
      buf.writeln(_row(['(no items in this period)']));
    } else {
      for (final i in items) {
        buf.writeln(_row([
          i.title,
          formatQty(i.quantity),
          i.unit ?? '',
          money(i.unitPrice),
          money(i.revenue),
        ]));
      }
    }
    buf.writeln();

    // —— Sale line detail ——
    buf.writeln(_row(['SALE DETAILS']));
    buf.writeln(_row([
      'Sale ID',
      'Date',
      'Customer',
      'Item',
      'Quantity',
      'Unit',
      'Unit price ($currency)',
      'Line total ($currency)',
      'Sale total ($currency)',
    ]));
    if (sales.isEmpty) {
      buf.writeln(_row(['(no sales in this period)']));
    } else {
      final ordered = [...sales]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final s in ordered) {
        final saleId = s.id.length >= 8
            ? s.id.substring(0, 8).toUpperCase()
            : s.id.toUpperCase();
        if (s.lines.isEmpty) {
          buf.writeln(_row([
            saleId,
            d(s.createdAt),
            s.customerName ?? 'Guest',
            '',
            '',
            '',
            '',
            '',
            money(s.total),
          ]));
          continue;
        }
        for (final l in s.lines) {
          buf.writeln(_row([
            saleId,
            d(s.createdAt),
            s.customerName ?? 'Guest',
            l.title,
            formatQty(l.quantity),
            l.unit ?? '',
            money(l.unitPrice),
            money(l.lineTotal),
            money(s.total),
          ]));
        }
      }
    }

    final file = File(p.join(dir.path, 'turnover_$stamp.csv'));
    await file.writeAsString(buf.toString(), flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Turnover export $stamp',
      ),
    );
  }

  Future<void> exportReceipts({
    required List<Sale> sales,
    required String currency,
    String? companyName,
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final dir = await getTemporaryDirectory();
    final buf = StringBuffer();

    String money(num v) => v.toStringAsFixed(2);
    String d(DateTime v) => DateFormat('yyyy-MM-dd HH:mm').format(v.toLocal());
    String rangeLabel() {
      if (from == null && to == null) return 'All time';
      final a = from == null ? '…' : DateFormat('yyyy-MM-dd').format(from);
      final b = to == null ? '…' : DateFormat('yyyy-MM-dd').format(to);
      return '$a to $b';
    }

    final totalRevenue = sales.fold<double>(0, (s, e) => s + e.total);

    buf.writeln(_row(['Receipts Export']));
    if (companyName != null && companyName.trim().isNotEmpty) {
      buf.writeln(_row(['Company', companyName.trim()]));
    }
    buf.writeln(_row(['Currency', currency]));
    buf.writeln(_row(['Period', rangeLabel()]));
    buf.writeln(_row(['Exported at', d(now)]));
    buf.writeln(_row(['Receipts count', '${sales.length}']));
    buf.writeln(_row(['Total revenue', money(totalRevenue)]));
    buf.writeln();

    buf.writeln(_row(['RECEIPTS']));
    buf.writeln(_row([
      'Sale ID',
      'Date',
      'Customer',
      'Item',
      'Quantity',
      'Unit',
      'Unit price ($currency)',
      'Line total ($currency)',
      'Sale total ($currency)',
    ]));

    if (sales.isEmpty) {
      buf.writeln(_row(['(no receipts in this period)']));
    } else {
      final sorted = [...sales]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final s in sorted) {
        final saleId = s.id.length >= 8
            ? s.id.substring(0, 8).toUpperCase()
            : s.id.toUpperCase();
        if (s.lines.isEmpty) {
          buf.writeln(_row([
            saleId,
            d(s.createdAt),
            s.customerName ?? 'Guest',
            '',
            '',
            '',
            '',
            '',
            money(s.total),
          ]));
          continue;
        }
        for (final l in s.lines) {
          buf.writeln(_row([
            saleId,
            d(s.createdAt),
            s.customerName ?? 'Guest',
            l.title,
            formatQty(l.quantity),
            l.unit ?? '',
            money(l.unitPrice),
            money(l.lineTotal),
            money(s.total),
          ]));
        }
      }
    }

    final file = File(p.join(dir.path, 'receipts_$stamp.csv'));
    await file.writeAsString(buf.toString(), flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Receipts export $stamp',
      ),
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
