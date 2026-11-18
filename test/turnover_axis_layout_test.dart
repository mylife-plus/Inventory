import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/turnover/turnover_period.dart';

List<double> _centers(int n, double l, double w, double barW) => [
      for (var i = 0; i < n; i++)
        turnoverBarCenterX(
          index: i,
          barCount: n,
          plotLeft: l,
          plotWidth: w,
          barWidth: barW,
        ),
    ];

/// Shared invariants: first + last bar labelled, inside the plot, no
/// overlap, and every label covers the bar whose date it shows.
void _check(
  List<TurnoverAxisLabelSlot> s,
  List<double> bars,
  double l,
  double r, {
  bool distinct = false,
}) {
  final n = bars.length;
  expect(s.first.barIndex, 0, reason: 'first bar labelled');
  expect(s.last.barIndex, n - 1, reason: 'last bar labelled');
  for (final x in s) {
    expect(x.left >= l - 1e-9, isTrue, reason: 'no left clip');
    expect(x.right <= r + 1e-9, isTrue, reason: 'no right clip');
    final b = bars[x.barIndex];
    expect(b >= x.left && b <= x.right, isTrue,
        reason: 'label ${x.text} must sit under its own bar');
  }
  for (var i = 1; i < s.length; i++) {
    expect(s[i].left >= s[i - 1].right, isTrue, reason: 'no overlap');
    expect(s[i].barIndex > s[i - 1].barIndex, isTrue);
  }
  if (distinct) expect(s.map((e) => e.text).toSet().length, s.length);
}

/// Every label exactly centred on its bar, except ends nudged inside.
void _expectCentredOnBars(
  List<TurnoverAxisLabelSlot> s,
  List<double> bars,
  double l,
  double r,
) {
  for (final x in s) {
    final b = bars[x.barIndex];
    final ideal = b - x.width / 2;
    final clamped = ideal.clamp(l, r - x.width);
    expect(x.left, closeTo(clamped, 1e-9), reason: x.text);
  }
}

void main() {
  const l = 30.0, r = 330.0;

  test('day 2w/1m: 3 labels, middle at plot centre, ends flush', () {
    for (final n in [14, 15, 30, 31, 32, 62]) {
      final bars = _centers(n, l, r - l, 6);
      final texts = [for (var i = 0; i < n; i++) '${i + 1}. Okt'];
      final s = turnoverAxisLabelLayout(
        plotLeft: l,
        plotRight: r,
        barCenters: bars,
        texts: texts,
        widths: [for (final _ in texts) 28.0],
        grain: TurnoverAxisGrain.day,
      );
      expect(s.length, 3, reason: 'n=$n');
      expect(s[0].left, closeTo(l, 1e-9));
      expect(s[2].right, closeTo(r, 1e-9));
      expect(s[1].center, closeTo((l + r) / 2, 1e-9));
      _check(s, bars, l, r);
    }
  });

  test('short day range: every date centred under its bar', () {
    final bars = _centers(5, l, r - l, 8);
    final texts = [for (var i = 0; i < 5; i++) '${i + 1}. Nov'];
    final s = turnoverAxisLabelLayout(
      plotLeft: l,
      plotRight: r,
      barCenters: bars,
      texts: texts,
      widths: [for (final _ in texts) 28.0],
      grain: TurnoverAxisGrain.day,
    );
    expect(s.length, 5);
    _check(s, bars, l, r);
    _expectCentredOnBars(s, bars, l, r);
  });

  for (final n in [3, 6, 12]) {
    test('month $n bars (3m/6m/1y): every label centred under its bar', () {
      final bars = _centers(n, l, r - l, 14);
      final texts = [for (var i = 0; i < n; i++) 'M$i'];
      final s = turnoverAxisLabelLayout(
        plotLeft: l,
        plotRight: r,
        barCenters: bars,
        texts: texts,
        widths: [for (final _ in texts) 16.0],
        grain: TurnoverAxisGrain.month,
      );
      expect(s.length, n);
      _check(s, bars, l, r);
      _expectCentredOnBars(s, bars, l, r);
    });
  }

  test('month 2y (24 bars): constant 2-bar step, labels under bars', () {
    final bars = _centers(24, l, r - l, 8);
    final texts = [for (var i = 0; i < 24; i++) "M$i"];
    final s = turnoverAxisLabelLayout(
      plotLeft: l,
      plotRight: r,
      barCenters: bars,
      texts: texts,
      widths: [for (final _ in texts) 18.0],
      grain: TurnoverAxisGrain.month,
    );
    expect(s.length, lessThan(24));
    _check(s, bars, l, r);
    expect(s.first.left, closeTo(l, 1e-9));
    expect(s.last.right, closeTo(r, 1e-9));
    for (var i = 1; i < s.length; i++) {
      final step = s[i].barIndex - s[i - 1].barIndex;
      expect(step >= 2 && step <= 3, isTrue, reason: 'no 1-bar steps');
    }
    // Middle labels exactly centred on their bars.
    for (final x in s.sublist(1, s.length - 1)) {
      expect(x.center, closeTo(bars[x.barIndex], 1e-9));
    }
  });

  test('year-only (>24 months): ends flush, no duplicate year, under bars', () {
    // Aug 2024 … Nov 2026 = 28 bars.
    final bars = _centers(28, l, r - l, 6);
    final texts = [for (var i = 0; i < 28; i++) '${2024 + (i + 7) ~/ 12}'];
    final s = turnoverAxisLabelLayout(
      plotLeft: l,
      plotRight: r,
      barCenters: bars,
      texts: texts,
      widths: [for (final _ in texts) 18.0],
      grain: TurnoverAxisGrain.month,
      distinctTexts: true,
    );
    _check(s, bars, l, r, distinct: true);
    expect(s.map((e) => e.text), ['2024', '2025', '2026']);
  });
}
