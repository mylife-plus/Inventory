import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/turnover/turnover_averages.dart';

void main() {
  group('calendarDaysInclusive', () {
    test('same day → 1', () {
      final d = DateTime(2026, 10, 23);
      expect(calendarDaysInclusive(d, d), 1);
    });

    test('12.12.2025–02.04.2026 inclusive day count', () {
      final from = DateTime(2025, 12, 12);
      final to = DateTime(2026, 4, 2);
      expect(calendarDaysInclusive(from, to), 112);
    });
  });

  group('TurnoverAverages.fromTotal', () {
    test('zero total → zeros', () {
      final a = TurnoverAverages.fromTotal(
        total: 0,
        from: DateTime(2026, 9, 23),
        to: DateTime(2026, 10, 23),
      );
      expect(a.dayAvg, 0);
      expect(a.monthAvg, 0);
      expect(a.yearAvg, 0);
    });

    test('day = total/days; month = day×30.44; year = day×365.24', () {
      const total = 1120.0;
      final from = DateTime(2025, 12, 12);
      final to = DateTime(2026, 4, 2);
      final days = calendarDaysInclusive(from, to);
      final a = TurnoverAverages.fromTotal(total: total, from: from, to: to);
      final day = total / days;
      expect(a.dayAvg, closeTo(day, 1e-9));
      expect(a.monthAvg, closeTo(day * 30.44, 1e-9));
      expect(a.yearAvg, closeTo(day * 365.24, 1e-9));
    });

    test('sparse sales do NOT inflate day avg', () {
      const total = 100.0;
      final a = TurnoverAverages.fromTotal(
        total: total,
        from: DateTime(2026, 9, 23),
        to: DateTime(2026, 10, 23),
      );
      expect(a.dayAvg, closeTo(100 / 31, 1e-9));
      expect(a.monthAvg, closeTo((100 / 31) * 30.44, 1e-9));
      expect(a.yearAvg, closeTo((100 / 31) * 365.24, 1e-9));
    });
  });
}
