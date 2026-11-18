
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventory_app/features/turnover/turnover_averages.dart';
import 'package:inventory_app/features/turnover/turnover_period.dart';

List<DateTime> _dayBuckets(DateTime from, DateTime to) {
  final out = <DateTime>[];
  var c = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  while (!c.isAfter(end)) {
    out.add(c);
    c = addCalendarDays(c, 1);
  }
  return out;
}

List<DateTime> _monthBuckets(DateTime from, DateTime to) {
  final out = <DateTime>[];
  var c = DateTime(from.year, from.month, 1);
  final end = DateTime(to.year, to.month, 1);
  while (!c.isAfter(end)) {
    out.add(c);
    c = DateTime(c.year, c.month + 1, 1);
  }
  return out;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de');
    await initializeDateFormatting('en');
  });

  group('turnoverPeriodFits — chip enablement', () {
    final now = DateTime(2026, 10, 29, 15, 0);

    test('All always fits', () {
      expect(
        turnoverPeriodFits(
          period: TurnoverPeriod.all,
          spanDays: 0,
          now: now,
        ),
        isTrue,
      );
    });

    test('2w enabled when span covers 14 inclusive days', () {
      // window=14 → need spanDays ≥ 13
      expect(
        turnoverPeriodFits(
          period: TurnoverPeriod.w2,
          spanDays: 13,
          now: now,
        ),
        isTrue,
      );
      expect(
        turnoverPeriodFits(
          period: TurnoverPeriod.w2,
          spanDays: 12,
          now: now,
        ),
        isFalse,
      );
    });

    test('2y disabled when history is only ~6 months', () {
      expect(
        turnoverPeriodFits(
          period: TurnoverPeriod.y2,
          spanDays: 180,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('turnoverPeriodSliderUnitRange — chip vs timeline', () {
    final now = DateTime(2026, 10, 29, 15, 0);

    test('2w on 200-day timeline → ~7% window at the end (0.93–1)', () {
      const timelineDays = 200;
      final window = turnoverPeriodWindowDays(TurnoverPeriod.w2, now);
      expect(window, 14);
      final u = turnoverPeriodSliderUnitRange(
        period: TurnoverPeriod.w2,
        timelineDays: timelineDays,
        now: now,
      );
      expect(u.$1, closeTo(1 - 14 / 200, 1e-9));
      expect(u.$2, 1);
    });

    test('All → full track', () {
      final u = turnoverPeriodSliderUnitRange(
        period: TurnoverPeriod.all,
        timelineDays: 200,
        now: now,
      );
      expect(u, (0, 1));
    });

    test('window longer than timeline → full track', () {
      final u = turnoverPeriodSliderUnitRange(
        period: TurnoverPeriod.y2,
        timelineDays: 30,
        now: now,
      );
      expect(u, (0, 1));
    });

    test('1y fraction sits at end', () {
      final window = turnoverPeriodWindowDays(TurnoverPeriod.y1, now);
      const timelineDays = 800;
      final u = turnoverPeriodSliderUnitRange(
        period: TurnoverPeriod.y1,
        timelineDays: timelineDays,
        now: now,
      );
      expect(u.$1, closeTo(1 - window / timelineDays, 1e-9));
      expect(u.$2, 1);
    });
  });

  group('turnoverPeriodBounds — exact bar windows', () {
    final now = DateTime(2026, 10, 29, 15, 0);

    test('2w: 14 inclusive days', () {
      final b = turnoverPeriodBounds(TurnoverPeriod.w2, now);
      expect(calendarDaysInclusive(b.$1, b.$2), 14);
      expect(startOfDay(b.$2), DateTime(2026, 10, 29), reason: 'ends today');
      expect(_dayBuckets(b.$1, b.$2).length, 14);
    });

    test('1m: one rolling calendar month of days', () {
      final b = turnoverPeriodBounds(TurnoverPeriod.m1, now);
      final days = _dayBuckets(b.$1, b.$2);
      expect(days.length, inInclusiveRange(28, 32));
    });

    test('3m / 6m / 1y / 2y: exact month counts', () {
      expect(
        _monthBuckets(
          turnoverPeriodBounds(TurnoverPeriod.m3, now).$1,
          turnoverPeriodBounds(TurnoverPeriod.m3, now).$2,
        ).length,
        3,
      );
      expect(
        _monthBuckets(
          turnoverPeriodBounds(TurnoverPeriod.m6, now).$1,
          turnoverPeriodBounds(TurnoverPeriod.m6, now).$2,
        ).length,
        6,
      );
      expect(
        _monthBuckets(
          turnoverPeriodBounds(TurnoverPeriod.y1, now).$1,
          turnoverPeriodBounds(TurnoverPeriod.y1, now).$2,
        ).length,
        12,
      );
      expect(
        _monthBuckets(
          turnoverPeriodBounds(TurnoverPeriod.y2, now).$1,
          turnoverPeriodBounds(TurnoverPeriod.y2, now).$2,
        ).length,
        24,
      );
    });
  });

  group('turnover fit + timeline division', () {
    const style = TextStyle(fontSize: 8, fontWeight: FontWeight.w600);

    test('fit count: wider plot allows more labels (no fixed lock)', () {
      final narrow = turnoverFitBarCount(
        plotWidth: 120,
        grain: TurnoverAxisGrain.month,
        locale: 'en',
        labelStyle: style,
      );
      final phone = turnoverFitBarCount(
        plotWidth: 280,
        grain: TurnoverAxisGrain.month,
        locale: 'en',
        labelStyle: style,
      );
      final wide = turnoverFitBarCount(
        plotWidth: 720,
        grain: TurnoverAxisGrain.month,
        locale: 'en',
        labelStyle: style,
      );
      expect(narrow, greaterThanOrEqualTo(kTurnoverMinFitBars));
      expect(phone, greaterThan(narrow));
      expect(wide, greaterThan(phone));
    });

    test('fit count respects maxCount (cannot exceed bars)', () {
      final fit = turnoverFitBarCount(
        plotWidth: 2000,
        grain: TurnoverAxisGrain.month,
        locale: 'en',
        labelStyle: style,
        maxCount: 6,
      );
      expect(fit, 6);
    });

    test('1m day: one bar per day; exactly 3 labels first/middle/last', () {
      const width = 320.0;
      final from = DateTime(2026, 10, 1);
      final to = DateTime(2026, 10, 31);
      final natural = turnoverChartBuckets(
        from: from,
        to: to,
        grain: TurnoverAxisGrain.day,
      );
      expect(natural.length, 31);
      final slots = turnoverBuildChartSlots(
        from: from,
        to: to,
        grain: TurnoverAxisGrain.day,
        fitCount: natural.length,
      );
      expect(slots.length, 31);
      expect(slots.first.start, DateTime(2026, 10, 1));
      expect(slots.last.end, DateTime(2026, 10, 31));
      final idxs = turnoverAxisLabelIndices(
        buckets: [for (final s in slots) s.labelDate],
        grain: TurnoverAxisGrain.day,
        rangeStart: from,
        rangeEnd: to,
        chartInnerWidth: width,
        locale: 'de',
        labelStyle: style,
      ).toList()
        ..sort();
      // 31 days (odd): true centre bar → gaps 15 + 15.
      expect(idxs, [0, 15, 30]);
      expect(turnoverDayMidLabelShiftsHalfBar(31), isFalse);
    });

    test('2w: 14 day bars; 3 labels, middle centred; last day present', () {
      final from = DateTime(2026, 10, 21);
      final to = DateTime(2026, 11, 3);
      final natural = turnoverChartBuckets(
        from: from,
        to: to,
        grain: TurnoverAxisGrain.day,
      );
      expect(natural.length, 14);
      final slots = turnoverBuildChartSlots(
        from: from,
        to: to,
        grain: TurnoverAxisGrain.day,
        fitCount: natural.length,
      );
      expect(slots.length, 14);
      expect(slots.first.labelDate, DateTime(2026, 10, 21));
      expect(slots.last.end, DateTime(2026, 11, 3));
      final idxs = turnoverAxisLabelIndices(
        buckets: [for (final s in slots) s.labelDate],
        grain: TurnoverAxisGrain.day,
        rangeStart: from,
        rangeEnd: to,
        chartInnerWidth: 400,
        locale: 'de',
        labelStyle: style,
      ).toList()
        ..sort();
      // 14 bars (even): no centre bar → label on bar 6, drawn half a bar to
      // the right, i.e. at 6.5 = exact centre of 0…13.
      expect(idxs, [0, 6, 13]);
      expect(turnoverDayMidLabelShiftsHalfBar(14), isTrue);
      expect(6 + 0.5, 13 / 2);
      // Day tooltip for a single bar is one date (not a range).
      expect(
        turnoverBucketTooltip(
          bucketStart: slots.last.labelDate,
          rangeStart: from,
          rangeEnd: to,
          grain: TurnoverAxisGrain.day,
          locale: 'de',
        ),
        isNot(contains('–')),
      );
    });

    test('equal-step indices always include last bar', () {
      expect(
        turnoverEqualStepLabelIndices(barCount: 14, step: 3).contains(13),
        isTrue,
      );
      expect(
        turnoverEqualStepLabelIndices(barCount: 13, step: 3),
        {0, 3, 6, 9, 12},
      );
    });

    test('dense charts keep a visible gap between bars (All / 62 days)', () {
      for (final n in [28, 40, 60, 62]) {
        for (final w in [240.0, 290.0, 340.0]) {
          final barW = turnoverComfortableBarWidth(
            plotWidth: w,
            barCount: n,
            maxBarWidth: 14,
          );
          final gap = (w - n * barW) / (n + 1);
          expect(gap, greaterThanOrEqualTo(2.0), reason: '$n bars, $w px');
          expect(barW, greaterThan(0));
        }
      }
    });

    test('comfortable bar width stays thick; day cap fits end labels', () {
      final barW = turnoverComfortableBarWidth(
        plotWidth: 280,
        barCount: 14,
        maxBarWidth: 8,
        widthFactor: 0.84,
      );
      expect(barW, greaterThanOrEqualTo(5));
      expect(turnoverEndLabelInset(40), closeTo(20, 0.01));
      expect(turnoverEndLabelInset(8), 8); // floor
      expect(turnoverEndLabelInset(80), 22); // cap
      final cap = turnoverDayBarCountForEndLabels(
        plotWidth: 280,
        halfEndLabelWidth: 20,
        naturalCount: 31,
      );
      expect(cap, lessThan(31));
      expect(cap, greaterThanOrEqualTo(8));
    });

    test('1m: 3 day labels at any width when dates do not all fit', () {
      final from = DateTime(2026, 10, 3);
      final to = DateTime(2026, 11, 3);
      final natural = _dayBuckets(from, to);
      final slots = turnoverBuildChartSlots(
        from: from,
        to: to,
        grain: TurnoverAxisGrain.day,
        fitCount: natural.length,
      );
      expect(slots.length, natural.length);
      expect(slots.last.end, DateTime(2026, 11, 3));
      final narrow = turnoverAxisLabelIndices(
        buckets: natural,
        grain: TurnoverAxisGrain.day,
        rangeStart: from,
        rangeEnd: to,
        chartInnerWidth: 220,
        locale: 'de',
        labelStyle: style,
      );
      final wide = turnoverAxisLabelIndices(
        buckets: natural,
        grain: TurnoverAxisGrain.day,
        rangeStart: from,
        rangeEnd: to,
        chartInnerWidth: 720,
        locale: 'de',
        labelStyle: style,
      );
      final n = natural.length;
      final expected = {0, turnoverDayMidLabelIndex(n), n - 1};
      expect(narrow, expected);
      expect(wide, expected);
    });

    test('short day range: every date when all fit', () {
      final from = DateTime(2026, 10, 1);
      final to = DateTime(2026, 10, 5);
      final natural = _dayBuckets(from, to);
      expect(natural.length, 5);
      final idxs = turnoverAxisLabelIndices(
        buckets: natural,
        grain: TurnoverAxisGrain.day,
        rangeStart: from,
        rangeEnd: to,
        chartInnerWidth: 400,
        locale: 'de',
        labelStyle: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600),
      );
      expect(idxs, {0, 1, 2, 3, 4});
    });

    test('day mid label: odd = centre bar, even = half-bar shift', () {
      for (var n = 4; n <= 62; n++) {
        final m = turnoverDayMidLabelIndex(n);
        final pos = m + (turnoverDayMidLabelShiftsHalfBar(n) ? 0.5 : 0.0);
        expect(pos, (n - 1) / 2, reason: '$n bars');
      }
    });

    test('3m: exactly 3 natural month bars (chip window)', () {
      final from3 = DateTime(2026, 9, 1);
      final to3 = DateTime(2026, 11, 3);
      final natural3 = _monthBuckets(from3, to3);
      expect(natural3.length, 3);
      final slots3 = turnoverBuildChartSlots(
        from: from3,
        to: to3,
        grain: TurnoverAxisGrain.month,
        fitCount: natural3.length,
      );
      expect(slots3.length, 3);
      final idxs = turnoverAxisLabelIndices(
        buckets: natural3,
        grain: TurnoverAxisGrain.month,
        rangeStart: from3,
        rangeEnd: to3,
        chartInnerWidth: 280,
        locale: 'en',
        labelStyle: style,
      );
      expect(idxs.length, 3);
    });

    test('1y/2y: every month is its own bar; last bar labeled', () {
      const width = 280.0;
      final from1y = DateTime(2025, 12, 1);
      final to1y = DateTime(2026, 11, 3);
      final from2y = DateTime(2024, 12, 1);
      final to2y = DateTime(2026, 11, 3);
      final n1 = _monthBuckets(from1y, to1y);
      final n2 = _monthBuckets(from2y, to2y);
      expect(n1.length, 12);
      expect(n2.length, 24);
      for (final entry in [
        (n1, from1y, to1y),
        (n2, from2y, to2y),
      ]) {
        final natural = entry.$1;
        final from = entry.$2;
        final to = entry.$3;
        // No merging: one bar per month (Oct must not fold into Nov).
        final slots = turnoverBuildChartSlots(
          from: from,
          to: to,
          grain: TurnoverAxisGrain.month,
          fitCount: natural.length,
        );
        expect(slots.length, natural.length);
        expect(slots.last.labelDate, DateTime(2026, 11, 1));
        expect(slots[slots.length - 2].labelDate, DateTime(2026, 10, 1));
        final idxs = turnoverAxisLabelIndices(
          buckets: [for (final s in slots) s.labelDate],
          grain: TurnoverAxisGrain.month,
          rangeStart: from,
          rangeEnd: to,
          chartInnerWidth: width,
          locale: 'en',
          labelStyle: style,
        ).toList()
          ..sort();
        // Last bar always labelled; equal steps back from it (the first
        // bar only when the step divides the span).
        expect(idxs.last, slots.length - 1);
        _expectEven(idxs);
        if (idxs.length > 1) expect(idxs.first, lessThan(idxs[1] - idxs[0]));
      }
    });

    test('even labels: all bars when they fit (1y/6m/3m month labels)', () {
      for (final (from, to, n) in [
        (DateTime(2025, 12, 1), DateTime(2026, 11, 9), 12),
        (DateTime(2026, 6, 1), DateTime(2026, 11, 9), 6),
        (DateTime(2026, 9, 1), DateTime(2026, 11, 9), 3),
        (DateTime(2026, 7, 9), DateTime(2026, 11, 1), 5),
      ]) {
        final natural = _monthBuckets(from, to);
        expect(natural.length, n);
        final idxs = turnoverAxisLabelIndices(
          buckets: natural,
          grain: TurnoverAxisGrain.month,
          rangeStart: from,
          rangeEnd: to,
          // The test font draws every glyph as a full em square (≈2× wider
          // than Inter), so use a wider plot to model a ~290 px phone plot.
          chartInnerWidth: 420,
          locale: 'en',
          labelStyle: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600),
        );
        expect(idxs, {for (var i = 0; i < n; i++) i}, reason: '$n months');
      }
    });

    test('even labels: never collide, ends kept, even gaps (any count)', () {
      for (var n = 2; n <= 62; n++) {
        for (final w in [180.0, 290.0, 420.0]) {
          for (final lw in [12.0, 25.0, 40.0]) {
            final idxs = turnoverEvenLabelIndices(
              barCount: n,
              plotWidth: w,
              labelWidth: lw,
            ).toList()
              ..sort();
            expect(idxs.last, n - 1);
            if (idxs.length > 1) {
              expect(idxs.first, lessThan(idxs[1] - idxs[0]));
            }
            final s0 = turnoverMinFitStep(
              barCount: n,
              plotWidth: w,
              labelWidth: lw,
            );
            for (var i = 1; i < idxs.length; i++) {
              if (idxs.length > 2) {
                expect(idxs[i] - idxs[i - 1], greaterThanOrEqualTo(s0));
              }
            }
            _expectEven(idxs);
          }
        }
      }
    });

    test('end-anchored labels keep first + last for any bar count', () {
      for (var n = 1; n <= 61; n++) {
        for (var step = 1; step <= 7; step++) {
          final idxs = turnoverEndAnchoredLabelIndices(barCount: n, step: step)
              .toList()
            ..sort();
          expect(idxs.first, 0);
          expect(idxs.last, n - 1);
        }
      }
    });

    test('>24 month bars: every label is the year only (no month)', () {
      final from = DateTime(2024, 10, 1);
      final to = DateTime(2026, 10, 29);
      expect(turnoverMonthBarCount(from, to), 25);
      final natural = _monthBuckets(from, to);
      expect(natural.length, 25);
      expect(
        turnoverMonthLabelsNeedYears(
          rangeStart: from,
          rangeEnd: to,
        ),
        isTrue,
      );
      final idxs = turnoverAxisLabelIndices(
        buckets: natural,
        grain: TurnoverAxisGrain.month,
        rangeStart: from,
        rangeEnd: to,
        chartInnerWidth: 300,
        locale: 'de',
        labelStyle: style,
      ).toList()
        ..sort();
      // Oct 2024 … Oct 2026: labels on each January only (equal 12-bar gaps).
      expect(idxs, [3, 15]);
      for (final i in idxs) {
        expect(natural[i].month, DateTime.january);
      }
      expect(
        turnoverAxisBarLabel(
          bucket: natural.first,
          grain: TurnoverAxisGrain.month,
          isFirstLabel: true,
          isLastLabel: false,
          rangeStart: from,
          rangeEnd: to,
          locale: 'de',
          monthLabelsNeedYears: true,
        ),
        '2024',
      );
      expect(
        turnoverAxisBarLabel(
          bucket: natural.last,
          grain: TurnoverAxisGrain.month,
          isFirstLabel: false,
          isLastLabel: true,
          rangeStart: from,
          rangeEnd: to,
          locale: 'de',
          monthLabelsNeedYears: true,
        ),
        '2026',
      );
      expect(
        turnoverAxisBarLabel(
          bucket: natural[idxs[0]],
          grain: TurnoverAxisGrain.month,
          isFirstLabel: false,
          isLastLabel: false,
          rangeStart: from,
          rangeEnd: to,
          locale: 'de',
          monthLabelsNeedYears: true,
        ),
        matches(RegExp(r'^\d{4}$')),
      );
    });

    test('>24 months (Aug 2024 – Nov 2026): one label per year, equal gaps', () {
      final from = DateTime(2024, 8, 27);
      final to = DateTime(2026, 11, 9);
      final natural = _monthBuckets(from, to);
      expect(natural.length, 28);
      final idxs = turnoverAxisLabelIndices(
        buckets: natural,
        grain: TurnoverAxisGrain.month,
        rangeStart: from,
        rangeEnd: to,
        chartInnerWidth: 300,
        locale: 'de',
        labelStyle: style,
      ).toList()
        ..sort();
      // Januaries 2025 and 2026 → exactly 12 bars apart.
      expect(idxs, [5, 17]);
      final labels = [
        for (final i in idxs)
          turnoverAxisBarLabel(
            bucket: natural[i],
            grain: TurnoverAxisGrain.month,
            isFirstLabel: i == idxs.first,
            isLastLabel: i == idxs.last,
            rangeStart: from,
            rangeEnd: to,
            locale: 'de',
            monthLabelsNeedYears: true,
          ),
      ];
      for (final l in labels) {
        expect(l, matches(RegExp(r'^\d{4}$')));
      }
      expect(labels.toSet().length, labels.length);
      expect(labels, ['2025', '2026']);
    });

    test('exactly 24 month bars: keep month-only labels (2y)', () {
      final from = DateTime(2024, 11, 1);
      final to = DateTime(2026, 10, 29);
      expect(turnoverMonthBarCount(from, to), 24);
      expect(
        turnoverMonthLabelsNeedYears(rangeStart: from, rangeEnd: to),
        isFalse,
      );
    });

    test('day range ending 1 Nov: last natural bar is 1 Nov', () {
      final from = DateTime(2026, 10, 19);
      final to = DateTime(2026, 11, 1);
      final days = turnoverChartBuckets(
        from: from,
        to: to,
        grain: TurnoverAxisGrain.day,
      );
      expect(days.last, DateTime(2026, 11, 1));
      expect(days.contains(DateTime(2026, 11, 2)), isFalse);
      expect(days.length, calendarDaysInclusive(from, to));
    });

    test('grain: >63 days → month; >60 months → year', () {
      expect(
        turnoverAxisGrainForRange(
          rangeStart: DateTime(2026, 1, 1),
          rangeEnd: DateTime(2026, 3, 4), // 63 days inclusive
        ),
        TurnoverAxisGrain.day,
      );
      expect(
        turnoverAxisGrainForRange(
          rangeStart: DateTime(2026, 1, 1),
          rangeEnd: DateTime(2026, 3, 5), // 64 days
        ),
        TurnoverAxisGrain.month,
      );
      expect(
        turnoverAxisGrainForRange(
          rangeStart: DateTime(2020, 1, 1),
          rangeEnd: DateTime(2024, 12, 1), // 60 months
        ),
        TurnoverAxisGrain.month,
      );
      expect(
        turnoverAxisGrainForRange(
          rangeStart: DateTime(2020, 1, 1),
          rangeEnd: DateTime(2025, 1, 1), // 61 months
        ),
        TurnoverAxisGrain.year,
      );
    });

    test('month year-labels only when more than 24 month bars', () {
      expect(
        turnoverMonthLabelsNeedYears(
          rangeStart: DateTime(2024, 11, 1),
          rangeEnd: DateTime(2026, 10, 1), // 24 months
          period: TurnoverPeriod.y2,
        ),
        isFalse,
      );
      expect(
        turnoverMonthLabelsNeedYears(
          rangeStart: DateTime(2024, 10, 1),
          rangeEnd: DateTime(2026, 10, 1), // 25 months
          period: TurnoverPeriod.all,
        ),
        isTrue,
      );
      expect(
        turnoverMonthLabelsNeedYears(
          rangeStart: DateTime(2025, 11, 1),
          rangeEnd: DateTime(2026, 10, 1), // 12 months
          period: TurnoverPeriod.y1,
        ),
        isFalse,
      );
    });

    test('≤12 month charts: month only (no year on January)', () {
      final from = DateTime(2025, 10, 1);
      final to = DateTime(2026, 10, 1);
      expect(
        turnoverMonthLabelsNeedYears(
          rangeStart: from,
          rangeEnd: to,
          period: TurnoverPeriod.y1,
        ),
        isFalse,
      );
      expect(
        turnoverAxisBarLabel(
          bucket: DateTime(2025, 10, 1),
          grain: TurnoverAxisGrain.month,
          isFirstLabel: true,
          rangeStart: from,
          rangeEnd: to,
          locale: 'de',
        ),
        'Okt',
      );
      expect(
        turnoverAxisBarLabel(
          bucket: DateTime(2026, 1, 1),
          grain: TurnoverAxisGrain.month,
          isFirstLabel: false,
          rangeStart: from,
          rangeEnd: to,
          locale: 'de',
          monthLabelsNeedYears: false,
        ),
        'Jan',
      );
    });

    test('All 3y month chart: start month+year, year anchors, end month+year', () {
      final from = DateTime(2024, 1, 1);
      final to = DateTime(2026, 10, 1);
      expect(
        turnoverMonthLabelsNeedYears(
          rangeStart: from,
          rangeEnd: to,
          period: TurnoverPeriod.all,
        ),
        isTrue,
      );
      expect(
        turnoverAxisBarLabel(
          bucket: DateTime(2024, 1, 1),
          grain: TurnoverAxisGrain.month,
          isFirstLabel: true,
          isLastLabel: false,
          rangeStart: from,
          rangeEnd: to,
          locale: 'en',
          monthLabelsNeedYears: true,
        ),
        '2024',
      );
      expect(
        turnoverAxisBarLabel(
          bucket: DateTime(2025, 1, 1),
          grain: TurnoverAxisGrain.month,
          isFirstLabel: false,
          isLastLabel: false,
          rangeStart: from,
          rangeEnd: to,
          locale: 'en',
          monthLabelsNeedYears: true,
        ),
        '2025',
      );
      expect(
        turnoverAxisBarLabel(
          bucket: DateTime(2026, 10, 1),
          grain: TurnoverAxisGrain.month,
          isFirstLabel: false,
          isLastLabel: true,
          rangeStart: from,
          rangeEnd: to,
          locale: 'en',
          monthLabelsNeedYears: true,
        ),
        '2026',
      );
    });

    test('chart buckets include empty months between sales', () {
      final buckets = turnoverChartBuckets(
        from: DateTime(2026, 1, 15),
        to: DateTime(2026, 4, 10),
        grain: TurnoverAxisGrain.month,
      );
      expect(buckets.length, 4);
      expect(buckets.first, DateTime(2026, 1, 1));
      expect(buckets.last, DateTime(2026, 4, 1));
    });

    test('year grain labels: equal step keeps first + last', () {
      final buckets = turnoverChartBuckets(
        from: DateTime(2000, 6, 1),
        to: DateTime(2012, 6, 1),
        grain: TurnoverAxisGrain.year,
      );
      expect(buckets.length, 13);
      final idxs = turnoverAxisLabelIndices(
        buckets: buckets,
        grain: TurnoverAxisGrain.year,
        rangeStart: buckets.first,
        rangeEnd: buckets.last,
        chartInnerWidth: 280,
        locale: 'en',
        labelStyle: style,
        period: TurnoverPeriod.all,
      ).toList()
        ..sort();
      expect(idxs.first, 0);
      expect(idxs.last, 12);
      expect(
        idxs.map((i) => buckets[i].year).toList(),
        containsAll([2000, 2012]),
      );
    });

    test('month tooltip is month + year (no day span)', () {
      expect(
        turnoverBucketTooltip(
          bucketStart: DateTime(2026, 4, 1),
          rangeStart: DateTime(2026, 4, 28),
          rangeEnd: DateTime(2026, 10, 28),
          grain: TurnoverAxisGrain.month,
          locale: 'de',
        ),
        'Apr 2026',
      );
      expect(
        turnoverBucketTooltip(
          bucketStart: DateTime(2026, 10, 1),
          rangeStart: DateTime(2026, 4, 28),
          rangeEnd: DateTime(2026, 10, 28),
          grain: TurnoverAxisGrain.month,
          locale: 'en',
        ),
        'Oct 2026',
      );
    });

    test('day tooltip keeps single day', () {
      expect(
        turnoverBucketTooltip(
          bucketStart: DateTime(2026, 10, 15),
          rangeStart: DateTime(2026, 10, 1),
          rangeEnd: DateTime(2026, 10, 31),
          grain: TurnoverAxisGrain.day,
          locale: 'en',
        ),
        '15. Oct 2026',
      );
    });

    test('nice Y scale: equal intervals, capped count', () {
      final s = turnoverYAxisScale(
        peak: 100,
        plotHeight: 160,
        maxIntervals: 5,
      );
      expect(s.tickCount, lessThanOrEqualTo(5));
      expect(s.maxY, greaterThanOrEqualTo(100));
      expect(s.maxY, s.interval * s.tickCount);
      expect(turnoverNiceCeil(3), 5);
      expect(turnoverNiceCeil(12), 20);
      expect(turnoverYAxisLabel(1500), '1.5k');
      expect(turnoverYAxisLabel(2000), '2k');
    });

    test('Y reserved size fits widest tick', () {
      const yStyle = TextStyle(fontSize: 9, fontWeight: FontWeight.w600);
      final scale = TurnoverYAxisScale(
        maxY: 5000,
        interval: 1000,
        tickCount: 5,
      );
      final reserved = turnoverYAxisReservedSize(
        scale: scale,
        labelStyle: yStyle,
      );
      final widest = turnoverMeasureLabelWidth('5k', yStyle);
      expect(reserved, greaterThanOrEqualTo(widest));
    });

    test('nearest bar: dense L→R and R→L sweeps visit every index', () {
      const plotW = 300.0;
      const n = 60;
      const barW = 3.0;
      // Walk left→right across the plot; indices must be non-decreasing and
      // eventually cover 0…n-1 (symmetric nearest-X, not leftmost-wins).
      final l2r = <int>[];
      for (var x = 0.0; x <= plotW; x += 0.5) {
        final i = turnoverNearestBarIndex(
          localX: x,
          plotWidth: plotW,
          barCount: n,
          barWidth: barW,
        );
        if (l2r.isEmpty || l2r.last != i) l2r.add(i);
      }
      expect(l2r.first, 0);
      expect(l2r.last, n - 1);
      for (var k = 1; k < l2r.length; k++) {
        expect(l2r[k], greaterThan(l2r[k - 1]));
      }
      expect(l2r, List.generate(n, (i) => i));

      final r2l = <int>[];
      for (var x = plotW; x >= 0; x -= 0.5) {
        final i = turnoverNearestBarIndex(
          localX: x,
          plotWidth: plotW,
          barCount: n,
          barWidth: barW,
        );
        if (r2l.isEmpty || r2l.last != i) r2l.add(i);
      }
      expect(r2l.first, n - 1);
      expect(r2l.last, 0);
      expect(r2l, List.generate(n, (i) => n - 1 - i));
    });

    test('touch horizontal pad never exceeds half spaceEvenly gap', () {
      const plotW = 280.0;
      const n = 62;
      const barW = 2.5;
      final pad = turnoverBarTouchHorizontalPad(
        plotWidth: plotW,
        barCount: n,
        barWidth: barW,
      );
      final eachSpace = (plotW - barW * n) / (n + 1);
      expect(pad, closeTo(eachSpace / 2, 1e-9));
      final centreSpacing = eachSpace + barW;
      expect(barW / 2 + pad, lessThanOrEqualTo(centreSpacing / 2 + 1e-9));
    });
  });
}


/// Gaps between consecutive labels are exactly one constant step (client:
/// equal visual spacing everywhere, no longer or shorter final gap).
void _expectEven(List<int> idxs) {
  if (idxs.length < 3) return;
  final gaps = [for (var i = 1; i < idxs.length; i++) idxs[i] - idxs[i - 1]];
  expect(gaps.toSet().length, 1, reason: 'all gaps must be equal: $gaps');
}
