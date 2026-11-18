import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/utils/date_bounds.dart';

void main() {
  group('DateBounds (filters / exports, Nov 11)', () {
    test('first / last record day, time of day ignored', () {
      final b = DateBounds.of([
        DateTime(2026, 3, 9, 18, 30),
        DateTime(2025, 12, 31, 23, 59),
        DateTime(2026, 1, 15, 8),
      ])!;
      expect(b.first, DateTime(2025, 12, 31));
      expect(b.last, DateTime(2026, 3, 9));
      expect(b.singleDay, isFalse);
    });

    test('empty data set gives null (callers show nothing)', () {
      expect(DateBounds.of(const []), isNull);
    });

    test('From picker ends the day before the last record', () {
      final b = DateBounds(DateTime(2026, 10, 1), DateTime(2026, 10, 20));
      final r = b.fromRange();
      expect(r.min, DateTime(2026, 10, 1));
      expect(r.max, DateTime(2026, 10, 19));
    });

    test('To picker starts at From + 1 day and ends at the last record', () {
      final b = DateBounds(DateTime(2026, 10, 1), DateTime(2026, 10, 20));
      final r = b.toRange(DateTime(2026, 10, 5));
      expect(r.min, DateTime(2026, 10, 6));
      expect(r.max, DateTime(2026, 10, 20));
      // Empty From counts as the first record day.
      expect(b.toRange(null).min, DateTime(2026, 10, 2));
      // Month / year boundary.
      final y = DateBounds(DateTime(2025, 12, 1), DateTime(2026, 2, 1));
      expect(y.toRange(DateTime(2025, 12, 31)).min, DateTime(2026, 1, 1));
    });

    test('changing From moves an invalid To, keeps a valid one', () {
      final b = DateBounds(DateTime(2026, 10, 1), DateTime(2026, 10, 20));
      expect(b.fixTo(DateTime(2026, 10, 10), DateTime(2026, 10, 3)),
          DateTime(2026, 10, 11));
      expect(b.fixTo(DateTime(2026, 10, 10), DateTime(2026, 10, 10)),
          DateTime(2026, 10, 11));
      expect(b.fixTo(DateTime(2026, 10, 2), DateTime(2026, 10, 15)),
          DateTime(2026, 10, 15));
      expect(b.fixTo(DateTime(2026, 10, 2), null), isNull);
    });

    test('single-day data: both pickers offer exactly that day', () {
      final b = DateBounds.of([
        DateTime(2026, 11, 11, 9),
        DateTime(2026, 11, 11, 17),
      ])!;
      expect(b.singleDay, isTrue);
      expect(b.fromRange(), (min: b.first, max: b.first));
      expect(b.toRange(b.first), (min: b.first, max: b.first));
      expect(b.fixTo(b.first, b.first), b.first);
    });

    test('two-day data: From = first, To = last only', () {
      final b = DateBounds(DateTime(2026, 11, 10), DateTime(2026, 11, 11));
      expect(b.fromRange(), (min: b.first, max: b.first));
      expect(b.toRange(b.first), (min: b.last, max: b.last));
    });

    test('min never above max, whatever From is', () {
      final b = DateBounds(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      for (var d = 0; d < 40; d++) {
        final r = b.toRange(DateTime(2025, 12, 25 + d));
        expect(r.min.isAfter(r.max), isFalse, reason: 'day $d');
      }
    });

    test('coversAll = no real filter', () {
      final b = DateBounds(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      expect(b.coversAll(null, null), isTrue);
      expect(b.coversAll(b.first, b.last), isTrue);
      expect(b.coversAll(DateTime(2026, 1, 2), b.last), isFalse);
      expect(b.coversAll(b.first, DateTime(2026, 1, 30)), isFalse);
    });

    test('addDays is calendar based (no 23 h / 25 h days)', () {
      expect(addDays(DateTime(2026, 3, 28), 1), DateTime(2026, 3, 29));
      expect(addDays(DateTime(2026, 3, 29), 1), DateTime(2026, 3, 30));
      expect(addDays(DateTime(2026, 10, 25), 1), DateTime(2026, 10, 26));
      expect(endOfDay(DateTime(2026, 3, 29, 5)),
          DateTime(2026, 3, 29, 23, 59, 59, 999));
    });
  });
}
