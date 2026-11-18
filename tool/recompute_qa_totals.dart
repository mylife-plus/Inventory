// Recompute Turnover QA expected totals with the app's own cent helpers.
// Run: dart run tool/recompute_qa_totals.dart

import 'dart:convert';
import 'dart:io';

import 'package:inventory_app/features/turnover/turnover_averages.dart';
import 'package:inventory_app/features/turnover/turnover_money.dart';
import 'package:inventory_app/features/turnover/turnover_period.dart';

void main() {
  final raw = File('sample_data/turnover_qa_26m.json').readAsStringSync();
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final sales = (data['sales'] as List).cast<Map<String, dynamic>>();
  final lines = (data['sale_lines'] as List).cast<Map<String, dynamic>>();
  final bySale = <String, List<Map<String, dynamic>>>{};
  for (final ln in lines) {
    bySale.putIfAbsent(ln['sale_id'] as String, () => []).add(ln);
  }

  final now = DateTime(2026, 10, 28, 15, 0);
  stdout.writeln('As-of $now (PKT calendar day 28 Oct 2026)');
  stdout.writeln(
    'Rule: lineCents = moneyToCents(unitPrice * quantity); sum cents',
  );
  stdout.writeln('Filter\tFrom\tDays\tTotal\tDay\tMonth\tYear');

  for (final period in [
    TurnoverPeriod.m6,
    TurnoverPeriod.y1,
    TurnoverPeriod.y2,
  ]) {
    final bounds = turnoverPeriodBounds(period, now);
    final from = bounds.$1;
    final to = bounds.$2;
    var cents = 0;
    for (final s in sales) {
      final at = DateTime.parse(s['created_at'] as String);
      if (at.isBefore(from) || at.isAfter(to)) continue;
      for (final ln in bySale[s['id'] as String] ?? const []) {
        cents += lineTotalCents(
          unitPrice: (ln['unit_price'] as num).toDouble(),
          quantity: (ln['quantity'] as num).toDouble(),
        );
      }
    }
    final total = centsToMoney(cents);
    final days = calendarDaysInclusive(from, to);
    final avg = TurnoverAverages.fromTotal(total: total, from: from, to: to);
    final label = switch (period) {
      TurnoverPeriod.m6 => '6m',
      TurnoverPeriod.y1 => '1y',
      TurnoverPeriod.y2 => '2y',
      _ => period.name,
    };
    stdout.writeln(
      '$label\t${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}'
      '\t$days\t${total.toStringAsFixed(2)}'
      '\t${avg.dayAvg.toStringAsFixed(2)}'
      '\t${avg.monthAvg.toStringAsFixed(2)}'
      '\t${avg.yearAvg.toStringAsFixed(2)}',
    );
  }
}
