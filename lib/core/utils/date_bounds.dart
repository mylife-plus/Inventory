/// Day-precision bounds of a data set (earliest → latest record day) and
/// the From / To picker rules shared by every date filter and export:
///
/// * From can be any day from the first record up to the day before the
///   last record (so a To of at least From + 1 day stays possible).
/// * To starts at From + 1 day (or first + 1 when From is empty) and ends
///   at the last record day.
/// * A data set that covers a single day only offers that one day for
///   both (no impossible range, no crash).
class DateBounds {
  DateBounds(DateTime first, DateTime last)
    : first = dayOf(first.isAfter(last) ? last : first),
      last = dayOf(first.isAfter(last) ? first : last);

  final DateTime first;
  final DateTime last;

  /// Earliest / latest day of [dates]; null when there are none.
  static DateBounds? of(Iterable<DateTime> dates) {
    DateTime? lo, hi;
    for (final d in dates) {
      if (lo == null || d.isBefore(lo)) lo = d;
      if (hi == null || d.isAfter(hi)) hi = d;
    }
    if (lo == null || hi == null) return null;
    return DateBounds(lo, hi);
  }

  bool get singleDay => !last.isAfter(first);

  DateTime clamp(DateTime d) {
    final day = dayOf(d);
    if (day.isBefore(first)) return first;
    if (day.isAfter(last)) return last;
    return day;
  }

  /// Selectable days of the From picker.
  ({DateTime min, DateTime max}) fromRange() =>
      (min: first, max: singleDay ? first : addDays(last, -1));

  /// Selectable days of the To picker for the chosen [from].
  ({DateTime min, DateTime max}) toRange(DateTime? from) {
    if (singleDay) return (min: first, max: first);
    var min = addDays(clamp(from ?? first), 1);
    if (min.isAfter(last)) min = last;
    return (min: min, max: last);
  }

  /// After From changed: keep To when it is still valid, otherwise move it
  /// to the nearest valid day. A null (open) To stays open.
  DateTime? fixTo(DateTime from, DateTime? to) {
    if (to == null) return null;
    final r = toRange(from);
    final day = dayOf(to);
    if (day.isBefore(r.min)) return r.min;
    if (day.isAfter(r.max)) return r.max;
    return day;
  }

  /// True when [from]..[to] covers the whole data set (no real filter).
  bool coversAll(DateTime? from, DateTime? to) =>
      (from == null || !dayOf(from).isAfter(first)) &&
      (to == null || !dayOf(to).isBefore(last));
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day arithmetic (DST-safe: no 24 h Duration math).
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Last moment of [d]'s day — inclusive end of a "To" filter.
DateTime endOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
