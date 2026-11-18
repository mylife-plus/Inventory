// Run also with a DST timezone, e.g. `TZ=Europe/Berlin flutter test`
// (client phone: CET/CEST; clocks went back on 25 Oct 2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/turnover/turnover_averages.dart';
import 'package:inventory_app/features/turnover/turnover_period.dart';

void main() {
  test('day buckets are inclusive calendar days across DST (8 Sep → 9 Nov)', () {
    final from = DateTime(2026, 9, 8);
    final to = DateTime(2026, 11, 9);
    final b = turnoverChartBuckets(from: from, to: to, grain: TurnoverAxisGrain.day);
    expect(b.length, 63);
    expect(b.first, DateTime(2026, 9, 8));
    expect(b.last, DateTime(2026, 11, 9), reason: 'last bar IS the end date');
    for (var i = 0; i < b.length; i++) {
      expect(b[i].hour, 0, reason: 'midnight, not 23:00 of the day before');
      expect(b[i], DateTime(2026, 9, 8 + i));
    }
    // Spring-forward too (29 Mar 2026).
    final s = turnoverChartBuckets(
      from: DateTime(2026, 3, 20),
      to: DateTime(2026, 4, 5),
      grain: TurnoverAxisGrain.day,
    );
    expect(s.length, 17);
    expect(s.last, DateTime(2026, 4, 5));
  });

  test('8 Sep → 9 Nov (63 days) stays day bars; 64 days → months', () {
    expect(
      turnoverAxisGrainForRange(
        rangeStart: DateTime(2026, 9, 8),
        rangeEnd: DateTime(2026, 11, 9),
      ),
      TurnoverAxisGrain.day,
    );
    expect(
      turnoverAxisGrainForRange(
        rangeStart: DateTime(2026, 9, 7),
        rangeEnd: DateTime(2026, 11, 9),
      ),
      TurnoverAxisGrain.month,
    );
  });

  test('calendarDaysInclusive and addCalendarDays ignore DST hours', () {
    expect(calendarDaysInclusive(DateTime(2026, 3, 20), DateTime(2026, 4, 5)), 17);
    expect(calendarDaysInclusive(DateTime(2026, 10, 20), DateTime(2026, 11, 9)), 21);
    expect(addCalendarDays(DateTime(2026, 9, 8), 62), DateTime(2026, 11, 9));
    expect(addCalendarDays(DateTime(2026, 3, 28), 1), DateTime(2026, 3, 29));
    expect(addCalendarDays(DateTime(2026, 11, 9), -13), DateTime(2026, 10, 27));
  });

  test('day slot sums its own day across DST (no shifted / doubled day)', () {
    final dayCents = {
      turnoverDayKey(DateTime(2026, 11, 8)): 100,
      turnoverDayKey(DateTime(2026, 11, 9)): 900,
    };
    final slots = turnoverBuildChartSlots(
      from: DateTime(2026, 9, 8),
      to: DateTime(2026, 11, 9),
      grain: TurnoverAxisGrain.day,
      fitCount: 63,
    );
    expect(slots.last.start, DateTime(2026, 11, 9));
    expect(slots.last.end, DateTime(2026, 11, 9));
    expect(turnoverSlotCents(slot: slots.last, dayCents: dayCents), 900);
    expect(turnoverSlotCents(slot: slots[slots.length - 2], dayCents: dayCents), 100);
  });

  test('period chips end on today (inclusive), first day correct', () {
    final now = DateTime(2026, 11, 9, 19, 37);
    for (final p in TurnoverPeriod.values) {
      final (f, t) = turnoverPeriodBounds(p, now);
      expect(startOfDay(t), DateTime(2026, 11, 9), reason: '$p ends today');
      expect(f.hour, 0);
    }
    expect(turnoverPeriodBounds(TurnoverPeriod.w2, now).$1, DateTime(2026, 10, 27));
    // Last month bar = current month.
    final (f, t) = turnoverPeriodBounds(TurnoverPeriod.y1, now);
    final m = turnoverChartBuckets(from: f, to: t, grain: TurnoverAxisGrain.month);
    expect(m.length, 12);
    expect(m.last, DateTime(2026, 11, 1));
  });
}
