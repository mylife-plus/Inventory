import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/turnover/turnover_averages.dart';
import 'package:inventory_app/features/turnover/turnover_period.dart';

void main() {
  test('one bar per unit: day / month / year, ends = range', () {
    for (final (from, to, grain, n) in [
      (DateTime(2026, 10, 27), DateTime(2026, 11, 9), TurnoverAxisGrain.day, 14),
      (DateTime(2026, 10, 9), DateTime(2026, 11, 9), TurnoverAxisGrain.day, 32),
      (DateTime(2026, 9, 1), DateTime(2026, 11, 1), TurnoverAxisGrain.day, 62),
      (DateTime(2026, 7, 9), DateTime(2026, 11, 1), TurnoverAxisGrain.month, 5),
      (DateTime(2024, 12, 1), DateTime(2026, 11, 9), TurnoverAxisGrain.month, 24),
      (DateTime(2024, 8, 27), DateTime(2026, 11, 9), TurnoverAxisGrain.month, 28),
      (DateTime(2019, 1, 5), DateTime(2026, 11, 9), TurnoverAxisGrain.year, 8),
    ]) {
      final slots = turnoverBuildChartSlots(
        from: from,
        to: to,
        grain: grain,
        fitCount: turnoverChartBuckets(from: from, to: to, grain: grain).length,
      );
      expect(slots.length, n, reason: '$from–$to');
      expect(slots.first.start, from);
      expect(slots.last.end, to);
      if (grain == TurnoverAxisGrain.day) {
        for (final s in slots) {
          expect(s.start, s.end, reason: 'one day per bar');
        }
      }
      for (var i = 1; i < slots.length; i++) {
        expect(slots[i].start, addCalendarDays(slots[i - 1].end, 1));
      }
    }
  });

  test('labels: every n 2–62 × widths → both ends, no overlap, near-equal', () {
    for (final plotW in [250.0, 300.0, 340.0]) {
      for (final labelW in [12.0, 16.0, 20.0, 24.0]) {
        for (var n = 2; n <= 63; n++) {
          final pitch = (plotW - labelW) / (n - 1);
          final idx = turnoverUnitLabelBars(
            barCount: n,
            pitch: pitch,
            labelWidth: labelW,
          );
          final why = 'n=$n w=$labelW plot=$plotW idx=$idx';
          expect(idx.first, 0, reason: why);
          expect(idx.last, n - 1, reason: why);
          final steps = [for (var i = 1; i < idx.length; i++) idx[i] - idx[i - 1]];
          for (final s in steps) {
            expect(s * pitch >= labelW + 5 - 1e-9, isTrue, reason: 'overlap $why');
          }
          final lo = steps.reduce((a, b) => a < b ? a : b);
          final hi = steps.reduce((a, b) => a > b ? a : b);
          expect(hi - lo, lessThanOrEqualTo(1), reason: 'gaps differ >1 bar $why');
          if (hi != lo) expect(lo, greaterThanOrEqualTo(2), reason: 'mixes 1/2 $why');
          // As many as fit: ≥ 50 % of the most labels on whole-bar steps.
          final kMin = ((labelW + 5) / pitch - 1e-9).ceil().clamp(1, n - 1);
          final maxFit = kMin <= 1 ? n : (n - 1) ~/ kMin + 1;
          final cap = turnoverLabelCap(maxFit);
          // v12: never crowd — when 8+ fit use ≤ min(7, fit−1).
          expect(idx.length, lessThanOrEqualTo(cap), reason: 'too many $why');
          if (maxFit >= 8) {
            expect(idx.length, lessThanOrEqualTo(7), reason: why);
            expect(idx.length, lessThanOrEqualTo(maxFit - 1), reason: why);
          }
          expect(idx.length >= (cap * 0.5).floor(), isTrue, reason: why);
          // Exactly equal whenever (N-1) has the chosen step as divisor.
          if (hi == lo) expect((n - 1) % lo, 0);
        }
      }
    }
  });

  test('v12 fewer labels: 12 fit → ≤7 (1y), ≤7 fit → all kept (6m)', () {
    final y = turnoverUnitLabelBars(barCount: 12, pitch: 27, labelWidth: 14);
    expect(y.length, inInclusiveRange(5, 7));
    expect(y.first, 0);
    expect(y.last, 11);
    final m6 = turnoverUnitLabelBars(barCount: 6, pitch: 60, labelWidth: 20);
    expect(m6, [0, 1, 2, 3, 4, 5]);
    expect(turnoverLabelCap(8), 7);
    expect(turnoverLabelCap(12), 7);
    expect(turnoverLabelCap(7), 7);
    expect(turnoverLabelCap(5), 5);
    // 2w / 1m / 63-day ranges with room for many labels → 6–7.
    for (final n in [14, 32, 63]) {
      final idx = turnoverUnitLabelBars(
        barCount: n,
        pitch: 330 / (n - 1),
        labelWidth: 30,
      );
      expect(idx.length, inInclusiveRange(5, 7), reason: 'n=$n $idx');
    }
  });

  test('year-only (>24 months): distinct years, ends labelled', () {
    for (var m = 25; m <= 60; m++) {
      for (var start = 1; start <= 12; start++) {
        final texts = [for (var i = 0; i < m; i++) '${2020 + (start - 1 + i) ~/ 12}'];
        final idx = turnoverUnitLabelBars(
          barCount: m,
          pitch: 300 / (m - 1),
          labelWidth: 16,
          texts: texts,
          distinctTexts: true,
        );
        final shown = [for (final i in idx) texts[i]];
        expect(shown.toSet().length, shown.length, reason: 'm=$m s=$start');
        expect(idx.first, 0);
        expect(idx.last, m - 1);
      }
    }
  });
}
