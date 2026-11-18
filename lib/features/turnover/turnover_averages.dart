// Pure turnover average helpers (testable).
// Filtered cashflow over the selected period window:
// day = total ÷ inclusive calendar days; month = day×30.44; year = day×365.24.

/// [d]'s calendar day plus [days] (local midnight). Never use
/// `add(Duration(days: n))` for calendar days: across a DST change (e.g. CET
/// 25 Oct) 24 h lands on 23:00 of the previous day and shifts every bar.
DateTime addCalendarDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

int calendarDaysInclusive(DateTime from, DateTime to) {
  // UTC dates: a local-midnight difference across DST is 23/25 h.
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  if (b.isBefore(a)) return 1;
  return b.difference(a).inDays + 1;
}

/// Mean calendar-month length used for month average scaling.
const double kTurnoverAvgDaysPerMonth = 30.44;

/// Mean calendar-year length used for year average scaling.
const double kTurnoverAvgDaysPerYear = 365.24;

class TurnoverAverages {
  const TurnoverAverages({
    required this.yearAvg,
    required this.monthAvg,
    required this.dayAvg,
    required this.total,
  });

  final double yearAvg;
  final double monthAvg;
  final double dayAvg;
  final double total;

  /// [total] = filtered revenue in range; [from]/[to] = effective filter window.
  factory TurnoverAverages.fromTotal({
    required double total,
    required DateTime from,
    required DateTime to,
  }) {
    if (total <= 0) {
      return const TurnoverAverages(
        yearAvg: 0,
        monthAvg: 0,
        dayAvg: 0,
        total: 0,
      );
    }
    final days = calendarDaysInclusive(from, to);
    final dayAvg = total / days;
    return TurnoverAverages(
      dayAvg: dayAvg,
      monthAvg: dayAvg * kTurnoverAvgDaysPerMonth,
      yearAvg: dayAvg * kTurnoverAvgDaysPerYear,
      total: total,
    );
  }
}
