import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';
import 'package:inventory_app/features/turnover/turnover_averages.dart';

/// Period chips on the Turnover screen.
enum TurnoverPeriod { w2, m1, m3, m6, y1, y2, all }

/// X-axis / bar grouping for the turnover chart.
enum TurnoverAxisGrain { day, month, year }

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime endOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// Calendar months before [from], clamping the day for short months / leap years.
DateTime calendarMonthsBefore(DateTime from, int months) {
  final totalMonths = from.year * 12 + (from.month - 1) - months;
  final y = totalMonths ~/ 12;
  final m = totalMonths % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  final d = from.day > lastDay ? lastDay : from.day;
  return DateTime(y, m, d);
}

/// Calendar years before [from], clamping Feb 29 → Feb 28 in non-leap years.
DateTime calendarYearsBefore(DateTime from, int years) {
  final y = from.year - years;
  final lastDay = DateTime(y, from.month + 1, 0).day;
  final d = from.day > lastDay ? lastDay : from.day;
  return DateTime(y, from.month, d);
}

/// First calendar day of the month [monthsBack] months before [from]'s month.
///
/// Example: Oct 2026, monthsBack=2 → 1 Aug 2026 (Aug+Sep+Oct = 3 months).
DateTime startOfMonthMonthsBack(DateTime from, int monthsBack) {
  return DateTime(from.year, from.month - monthsBack, 1);
}

/// Inclusive period window ending at end-of-today ([now]).
///
/// Month chips (3m/6m/1y/2y) start on the 1st so the chart has exactly
/// 3 / 6 / 12 / 24 month bars. Day chips (2w/1m) stay rolling day windows.
(DateTime from, DateTime to) turnoverPeriodBounds(
  TurnoverPeriod period,
  DateTime now,
) {
  final end = endOfDay(now);
  final today = startOfDay(now);
  switch (period) {
    case TurnoverPeriod.w2:
      return (addCalendarDays(today, -13), end);
    case TurnoverPeriod.m1:
      return (startOfDay(calendarMonthsBefore(today, 1)), end);
    case TurnoverPeriod.m3:
      return (startOfMonthMonthsBack(today, 2), end);
    case TurnoverPeriod.m6:
      return (startOfMonthMonthsBack(today, 5), end);
    case TurnoverPeriod.y1:
      return (startOfMonthMonthsBack(today, 11), end);
    case TurnoverPeriod.y2:
      return (startOfMonthMonthsBack(today, 23), end);
    case TurnoverPeriod.all:
      // Wide ceiling; slider / data clamp the visible range.
      return (startOfDay(calendarYearsBefore(today, 10)), end);
  }
}

/// Inclusive calendar days in the chip window as of [now].
int turnoverPeriodWindowDays(TurnoverPeriod period, DateTime now) {
  if (period == TurnoverPeriod.all) return 0;
  final b = turnoverPeriodBounds(period, now);
  return calendarDaysInclusive(b.$1, b.$2);
}

/// Unit-range slider thumbs for a period chip over [timelineDays] of history.
///
/// The chip window sits at the **end** (most recent). Example: 2w = 14 days on
/// a 200-day timeline → `(0.93, 1.0)` so the selected band is 7% at the end.
/// [All](TurnoverPeriod.all) or oversized windows → `(0, 1)`.
(double start, double end) turnoverPeriodSliderUnitRange({
  required TurnoverPeriod period,
  required int timelineDays,
  required DateTime now,
}) {
  if (period == TurnoverPeriod.all || timelineDays <= 0) {
    return (0, 1);
  }
  final window = turnoverPeriodWindowDays(period, now);
  if (window <= 0) return (0, 1);
  final fraction = (window / timelineDays).clamp(0.0, 1.0);
  if (fraction >= 0.999) return (0, 1);
  return (1.0 - fraction, 1.0);
}

/// Enable a period chip when the sale data span covers that window.
///
/// [spanDays] is `maxSale.difference(minSale).inDays` (exclusive-end style,
/// matching existing callers). A window of N inclusive days needs span ≥ N-1.
bool turnoverPeriodFits({
  required TurnoverPeriod period,
  required int spanDays,
  required DateTime now,
}) {
  if (period == TurnoverPeriod.all) return true;
  final window = turnoverPeriodWindowDays(period, now);
  if (window <= 1) return spanDays >= 0;
  return spanDays >= window - 1;
}

/// Max day bars before switching to month grain. v12: 63 so any
/// "two calendar months back → today" window (inclusive, up to 31+31+1 days,
/// e.g. 8 Sep → 9 Nov) stays day bars now that today is the inclusive end.
const int kTurnoverMaxDayBars = 63;

/// Max month bars before switching to year grain (client: after 60 months).
const int kTurnoverMaxMonthBars = 60;

/// Above this many *natural* month bars: ends = month+year, middles = years.
/// Exactly 24 (e.g. 2y chip) keeps normal month labels (client: more than 24).
const int kTurnoverMonthYearLabelAt = 24;

/// Fallback label count when plot width cannot be measured.
const int kTurnoverPreferredLabelCount = 8;

/// Minimum x-label count (always keep at least ends when ≥2 bars).
const int kTurnoverMinFitBars = 2;

/// Inclusive calendar-month bar count from [from]…[to].
int turnoverMonthBarCount(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, 1);
  final b = DateTime(to.year, to.month, 1);
  if (b.isBefore(a)) return 1;
  return (b.year - a.year) * 12 + (b.month - a.month) + 1;
}

/// Grain from a concrete visible window (scrubbing / All).
TurnoverAxisGrain turnoverAxisGrainForRange({
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final days = calendarDaysInclusive(rangeStart, rangeEnd);
  if (days > kTurnoverMaxDayBars) {
    final months = turnoverMonthBarCount(rangeStart, rangeEnd);
    if (months > kTurnoverMaxMonthBars) return TurnoverAxisGrain.year;
    return TurnoverAxisGrain.month;
  }
  return TurnoverAxisGrain.day;
}

/// Axis grain: short chips stay day/month; long windows use 62d / 60m rules.
TurnoverAxisGrain turnoverAxisGrain({
  required TurnoverPeriod period,
  required int spanDays,
  DateTime? rangeStart,
  DateTime? rangeEnd,
}) {
  switch (period) {
    case TurnoverPeriod.w2:
    case TurnoverPeriod.m1:
      return TurnoverAxisGrain.day;
    case TurnoverPeriod.m3:
    case TurnoverPeriod.m6:
    case TurnoverPeriod.y1:
    case TurnoverPeriod.y2:
      if (rangeStart != null && rangeEnd != null) {
        if (turnoverMonthBarCount(rangeStart, rangeEnd) > kTurnoverMaxMonthBars) {
          return TurnoverAxisGrain.year;
        }
      }
      return TurnoverAxisGrain.month;
    case TurnoverPeriod.all:
      if (rangeStart != null && rangeEnd != null) {
        return turnoverAxisGrainForRange(
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );
      }
      // Fallback when only exclusive span days are known.
      final approxDays = spanDays + 1;
      if (approxDays > kTurnoverMaxDayBars) {
        if (spanDays > kTurnoverMaxMonthBars * 30) {
          return TurnoverAxisGrain.year;
        }
        return TurnoverAxisGrain.month;
      }
      return TurnoverAxisGrain.day;
  }
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

String _mmm(DateTime d, String locale) =>
    DateFormat.MMM(locale).format(d).replaceAll('.', '');

/// Inclusive calendar years touched by [rangeStart]…[rangeEnd] (e.g. Jan 2024
/// → Oct 2026 → 3).
int turnoverYearsTouched(DateTime rangeStart, DateTime rangeEnd) {
  final a = _d(rangeStart).year;
  final b = _d(rangeEnd).year;
  return (b - a) + 1;
}

/// Month-grain charts: when month bars **exceed** [kTurnoverMonthYearLabelAt],
/// label ends with month+year and intermediate ticks with years (client).
bool turnoverMonthLabelsNeedYears({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  TurnoverPeriod? period,
}) {
  // [period] kept for call-site compatibility; threshold is bar-count based.
  return turnoverMonthBarCount(rangeStart, rangeEnd) > kTurnoverMonthYearLabelAt;
}

/// Nearest bar index for a touch X under fl_chart [BarChartAlignment.spaceEvenly]
/// (equal gaps before/between/after so edge date labels are not clipped).
///
/// fl_chart's built-in hit test returns the **first** overlapping rod (left→right
/// scan). Callers should map touch X through this helper instead.
int turnoverNearestBarIndex({
  required double localX,
  required double plotWidth,
  required int barCount,
  required double barWidth,
}) {
  if (barCount <= 0) return 0;
  if (barCount == 1) return 0;
  final width = plotWidth <= 0 ? 1.0 : plotWidth;
  final rodW = barWidth.clamp(0.0, width).toDouble();
  final spaceAvailable = width - rodW * barCount;
  final eachSpace = spaceAvailable / (barCount + 1);
  var best = 0;
  var bestDist = double.infinity;
  var tempX = 0.0;
  for (var i = 0; i < barCount; i++) {
    tempX += eachSpace;
    tempX += rodW / 2;
    final d = (localX - tempX).abs();
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
    tempX += rodW / 2;
  }
  return best;
}

/// Horizontal touch pad that fills spaceEvenly gaps without overlapping
/// neighbours (avoids fl_chart leftmost-wins bias on dense charts).
double turnoverBarTouchHorizontalPad({
  required double plotWidth,
  required int barCount,
  required double barWidth,
}) {
  if (barCount <= 1) return 0;
  final width = plotWidth <= 0 ? 1.0 : plotWidth;
  final rodW = barWidth.clamp(0.0, width).toDouble();
  final spaceAvailable = math.max(0.0, width - rodW * barCount);
  return spaceAvailable / (2 * (barCount + 1));
}

/// Every *natural* chart bar slot from [from]…[to] for [grain] (includes empty
/// / zero spend buckets — callers may later divide these to a fit count).
List<DateTime> turnoverChartBuckets({
  required DateTime from,
  required DateTime to,
  required TurnoverAxisGrain grain,
}) {
  final rs = _d(from);
  final re = _d(to);
  if (re.isBefore(rs)) return const [];
  switch (grain) {
    case TurnoverAxisGrain.day:
      final out = <DateTime>[];
      var c = rs;
      while (!c.isAfter(re)) {
        out.add(c);
        c = addCalendarDays(c, 1);
      }
      return out;
    case TurnoverAxisGrain.month:
      final out = <DateTime>[];
      var c = DateTime(rs.year, rs.month, 1);
      final end = DateTime(re.year, re.month, 1);
      while (!c.isAfter(end)) {
        out.add(c);
        c = DateTime(c.year, c.month + 1, 1);
      }
      return out;
    case TurnoverAxisGrain.year:
      return [
        for (var y = rs.year; y <= re.year; y++) DateTime(y, 1, 1),
      ];
  }
}

/// One displayed bar after width-fit timeline division.
///
/// [start]/[end] are inclusive calendar days covered by the bar (for summing
/// + tooltips). [labelDate] is the anchor used for the x-axis title.
class TurnoverChartSlot {
  const TurnoverChartSlot({
    required this.start,
    required this.end,
    required this.labelDate,
  });

  final DateTime start;
  final DateTime end;
  final DateTime labelDate;
}

DateTime _bucketRangeStart(DateTime bucket, TurnoverAxisGrain grain, DateTime rangeStart) {
  final rs = _d(rangeStart);
  final b = _d(bucket);
  switch (grain) {
    case TurnoverAxisGrain.day:
      return b.isBefore(rs) ? rs : b;
    case TurnoverAxisGrain.month:
      final s = DateTime(b.year, b.month, 1);
      return s.isBefore(rs) ? rs : s;
    case TurnoverAxisGrain.year:
      final s = DateTime(b.year, 1, 1);
      return s.isBefore(rs) ? rs : s;
  }
}

DateTime _bucketRangeEnd(DateTime bucket, TurnoverAxisGrain grain, DateTime rangeEnd) {
  final re = _d(rangeEnd);
  final b = _d(bucket);
  late DateTime e;
  switch (grain) {
    case TurnoverAxisGrain.day:
      e = b;
    case TurnoverAxisGrain.month:
      e = DateTime(b.year, b.month + 1, 0);
    case TurnoverAxisGrain.year:
      e = DateTime(b.year, 12, 31);
  }
  return e.isAfter(re) ? re : e;
}

/// How many x-labels the plot width can hold (raw capacity).
///
/// Used as an upper bound for [turnoverAxisLabelIndices] fixed-step picking.
/// No preferred-count lock — equal **step** (min distance) is the source of
/// truth for spacing; locking a count caused uneven gaps (Feb next to Mar).
int turnoverFitBarCount({
  required double plotWidth,
  required TurnoverAxisGrain grain,
  String locale = 'en',
  TextStyle labelStyle = const TextStyle(
    fontSize: 7,
    fontWeight: FontWeight.w600,
  ),
  double labelGap = 8,
  int? maxCount,
  bool preferYearWidth = false,
}) {
  if (plotWidth <= 0) {
    final fallback = kTurnoverPreferredLabelCount;
    return maxCount == null ? fallback : math.min(fallback, maxCount);
  }
  // >24 months: labels are the year only (client), so size for '2026'.
  final sample = preferYearWidth
      ? '2026'
      : switch (grain) {
          TurnoverAxisGrain.day =>
            '28. ${_mmm(DateTime(2026, 9, 28), locale)}',
          TurnoverAxisGrain.month => _mmm(DateTime(2026, 9, 1), locale),
          TurnoverAxisGrain.year => '2026',
        };
  final labelW = turnoverMeasureLabelWidth(sample, labelStyle);
  final need = math.max(labelW + labelGap, 28.0);
  final byWidth = math.max(kTurnoverMinFitBars, (plotWidth / need).floor());
  if (maxCount != null) return byWidth.clamp(kTurnoverMinFitBars, maxCount);
  return byWidth;
}

bool turnoverIsPrime(int n) {
  if (n <= 1) return false;
  if (n <= 3) return true;
  if (n % 2 == 0 || n % 3 == 0) return false;
  for (var i = 5; i * i <= n; i += 6) {
    if (n % i == 0 || n % (i + 2) == 0) return false;
  }
  return true;
}

/// Min bar-index step so labels keep a readable gap for [barCount] / width.
int turnoverMinLabelStep({
  required int barCount,
  required double plotWidth,
  required TurnoverAxisGrain grain,
  String locale = 'en',
  TextStyle labelStyle = const TextStyle(
    fontSize: 7,
    fontWeight: FontWeight.w600,
  ),
  double labelGap = 8,
  bool preferYearWidth = false,
}) {
  final n = barCount;
  if (n <= 2) return 1;
  final fitCap = turnoverFitBarCount(
    plotWidth: plotWidth,
    grain: grain,
    locale: locale,
    labelStyle: labelStyle,
    labelGap: labelGap,
    maxCount: n,
    preferYearWidth: preferYearWidth,
  );
  var step = fitCap >= n
      ? 1
      : math.max(1, ((n - 1) / (fitCap - 1)).ceil());
  if (grain == TurnoverAxisGrain.day) {
    final minDayStep = n <= 16 ? 3 : (n <= 35 ? 7 : 14);
    step = math.max(step, minDayStep);
  }
  return step.clamp(1, n - 1);
}

/// Displayed bar count ≤ [naturalCount] so first→last labels can use one
/// constant step (avoids prime spans that only allow step 1 or “ends only”).
///
/// When needed, neighbouring natural buckets are merged via
/// [turnoverBuildChartSlots]. Label text format is unchanged.
int turnoverPreferEvenSpanBarCount({
  required int naturalCount,
  required int minStep,
}) {
  if (naturalCount <= 2) return naturalCount;
  final step = math.max(1, minStep);
  if (step <= 1) return naturalCount;

  var n = naturalCount;
  // Prefer a count where (n-1) is divisible by [step] → last index lands on grid.
  while (n > 2 && (n - 1) % step != 0) {
    n--;
  }
  // If the span is still prime, only step=span works (no even interiors) —
  // drop bars until the span is composite (or step fits).
  while (n > 2 && turnoverIsPrime(n - 1)) {
    n--;
    while (n > 2 && (n - 1) % step != 0) {
      n--;
    }
  }
  return math.max(2, n);
}

/// Fixed bar-index step so consecutive labels keep a **constant** gap
/// (label → skip → label…). Always includes the first and last bar.
Set<int> turnoverEqualStepLabelIndices({
  required int barCount,
  required int step,
}) {
  final n = barCount;
  if (n <= 0) return const <int>{};
  if (n == 1) return const {0};
  if (n == 2) return const {0, 1};
  var s = step.clamp(1, n - 1);
  // Bump step so the grid lands on the last bar (even spacing, ends kept).
  while (s < n - 1 && (n - 1) % s != 0) {
    s++;
  }
  return {for (var i = 0; i < n; i += s) i};
}

/// Side inset (px) so end labels have a little room outside the bar band.
double turnoverEndLabelInset(double endLabelWidth) {
  final half = endLabelWidth / 2;
  return half.clamp(8.0, 22.0);
}

/// Right-side inset — slightly larger than [turnoverEndLabelInset] because the
/// left already has Y-axis space while the right edge clips last-date labels.
double turnoverRightLabelInset(double endLabelWidth) {
  return (endLabelWidth / 2 + 4).clamp(12.0, 36.0);
}

/// Comfortable bar rod width with a visible gap — never needle-thin.
double turnoverComfortableBarWidth({
  required double plotWidth,
  required int barCount,
  required double maxBarWidth,
  double minBarWidth = 5.0,
  double minGap = 2.5,
  /// 1.0 = full width; ~0.85 leaves a bit more end gap for labels (1m days).
  double widthFactor = 1.0,
}) {
  final n = barCount;
  final width = plotWidth <= 0 ? 1.0 : plotWidth;
  if (n <= 0) return minBarWidth;
  if (n == 1) {
    return math.min(maxBarWidth, width).clamp(minBarWidth, maxBarWidth).toDouble();
  }
  final byGap = (width - minGap * (n - 1)) / n;
  final raw = math.min(maxBarWidth, byGap) * widthFactor.clamp(0.7, 1.0);
  // Dense charts (e.g. All / 60 months, 62 days): never widen bars past the
  // width that still leaves [minGap] between them — a visible gap always
  // wins over [minBarWidth] (client: bars must not touch).
  final floor = math.max(1.0, math.min(minBarWidth, byGap));
  return raw.clamp(floor, maxBarWidth).toDouble();
}

/// Max day bars so a centred end-label still fits with [BarChartAlignment.spaceEvenly].
///
/// Dense 1m (~30 days) cannot clear end dates with thick bars; cap merges a few
/// neighbouring days so bars stay readable and labels sit inside the plot.
int turnoverDayBarCountForEndLabels({
  required double plotWidth,
  required double halfEndLabelWidth,
  required int naturalCount,
}) {
  if (naturalCount <= 2) return naturalCount;
  final half = math.max(12.0, halfEndLabelWidth);
  // firstCenter ≈ plot/(n+1) when bars are modest → n+1 ≤ plot/half
  final cap = math.max(8, (plotWidth / half).floor() - 1);
  return math.min(naturalCount, cap);
}

/// Build displayed chart slots: at most [fitCount] bars covering [from]…[to].
///
/// If natural grain buckets ≤ [fitCount], each natural bucket is one bar.
/// Otherwise the natural timeline is divided into [fitCount] contiguous groups
/// (bars = labels = [fitCount]). Grain thresholds (62d / 60m) are applied by
/// the caller before choosing [grain].
List<TurnoverChartSlot> turnoverBuildChartSlots({
  required DateTime from,
  required DateTime to,
  required TurnoverAxisGrain grain,
  required int fitCount,
}) {
  final natural = turnoverChartBuckets(from: from, to: to, grain: grain);
  if (natural.isEmpty) return const [];
  final n = fitCount.clamp(1, natural.length);
  if (n >= natural.length) {
    return [
      for (final d in natural)
        TurnoverChartSlot(
          start: _bucketRangeStart(d, grain, from),
          end: _bucketRangeEnd(d, grain, to),
          labelDate: d,
        ),
    ];
  }
  // Divide natural indices into [n] contiguous groups.
  final out = <TurnoverChartSlot>[];
  for (var k = 0; k < n; k++) {
    final i0 = (k * natural.length) ~/ n;
    var i1 = (((k + 1) * natural.length) ~/ n) - 1;
    if (i1 < i0) i1 = i0;
    final a = natural[i0];
    final b = natural[i1];
    out.add(
      TurnoverChartSlot(
        start: _bucketRangeStart(a, grain, from),
        end: _bucketRangeEnd(b, grain, to),
        // Last bar labels the range end; earlier bars label the group start.
        labelDate: k == n - 1 ? b : a,
      ),
    );
  }
  return out;
}

/// `yyyy-MM-dd` key for day-level cashflow maps.
String turnoverDayKey(DateTime d) {
  final x = _d(d);
  final m = x.month.toString().padLeft(2, '0');
  final day = x.day.toString().padLeft(2, '0');
  return '${x.year}-$m-$day';
}

/// Sum [dayCents] over the inclusive [slot] day span.
int turnoverSlotCents({
  required TurnoverChartSlot slot,
  required Map<String, int> dayCents,
}) {
  var sum = 0;
  var c = _d(slot.start);
  final end = _d(slot.end);
  while (!c.isAfter(end)) {
    sum += dayCents[turnoverDayKey(c)] ?? 0;
    c = addCalendarDays(c, 1);
  }
  return sum;
}

/// Axis label text for one bar (locale-aware).
///
/// When [monthLabelsNeedYears] is true (>24 natural months) every label is the
/// **year only** (client: no month at the start/end, no two-line `Aug\n2026`).
String turnoverAxisBarLabel({
  required DateTime bucket,
  required TurnoverAxisGrain grain,
  required bool isFirstLabel,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required String locale,
  bool isLastLabel = false,
  bool monthLabelsNeedYears = false,
}) {
  final d = _d(bucket);
  return switch (grain) {
    TurnoverAxisGrain.year => '${d.year}',
    TurnoverAxisGrain.day => '${d.day}. ${_mmm(d, locale)}',
    TurnoverAxisGrain.month => () {
        final m = _mmm(d, locale);
        if (!monthLabelsNeedYears) return m;
        return '${d.year}';
      }(),
  };
}

/// Inclusive calendar range a bar covers within [rangeStart]…[rangeEnd].
(DateTime, DateTime) turnoverBucketCoveredRange({
  required DateTime bucketStart,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required TurnoverAxisGrain grain,
}) {
  final rs = _d(rangeStart);
  final re = _d(rangeEnd);
  final b = _d(bucketStart);
  late DateTime from;
  late DateTime to;
  switch (grain) {
    case TurnoverAxisGrain.day:
      from = b;
      to = b;
    case TurnoverAxisGrain.month:
      from = DateTime(b.year, b.month, 1);
      to = DateTime(b.year, b.month + 1, 0);
    case TurnoverAxisGrain.year:
      from = DateTime(b.year, 1, 1);
      to = DateTime(b.year, 12, 31);
  }
  if (from.isBefore(rs)) from = rs;
  if (to.isAfter(re)) to = re;
  if (to.isBefore(from)) to = from;
  return (from, to);
}

/// Tooltip date line for a bar (client: month = `Oct 2026`; merged slots show a span).
String turnoverBucketTooltip({
  required DateTime bucketStart,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required TurnoverAxisGrain grain,
  required String locale,
  DateTime? bucketEnd,
}) {
  final (from, toSingle) = turnoverBucketCoveredRange(
    bucketStart: bucketStart,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    grain: grain,
  );
  final to = bucketEnd == null
      ? toSingle
      : _bucketRangeEnd(bucketEnd, grain, rangeEnd);
  return switch (grain) {
    TurnoverAxisGrain.year => from.year == to.year
        ? '${from.year}'
        : '${from.year}–${to.year}',
    TurnoverAxisGrain.month => from.year == to.year && from.month == to.month
        ? '${_mmm(from, locale)} ${from.year}'
        : '${_mmm(from, locale)} ${from.year} – ${_mmm(to, locale)} ${to.year}',
    TurnoverAxisGrain.day => _d(from) == _d(to)
        ? '${from.day}. ${_mmm(from, locale)} ${from.year}'
        : '${from.day}. ${_mmm(from, locale)} – ${to.day}. ${_mmm(to, locale)} ${to.year}',
  };
}

double turnoverMeasureLabelWidth(String text, TextStyle style) {
  // Multi-line end labels (month\\nyear): width = widest line.
  var maxW = 0.0;
  for (final line in text.split('\n')) {
    final tp = TextPainter(
      text: TextSpan(text: line, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width < 1 ? line.length * 5.0 : tp.width;
    if (w > maxW) maxW = w;
  }
  return maxW;
}

/// Exactly three x-label indices for day charts: first, middle, last.
Set<int> turnoverDayThreeLabelIndices(int barCount) {
  final n = barCount;
  if (n <= 0) return const <int>{};
  if (n == 1) return const {0};
  if (n == 2) return const {0, 1};
  if (n == 3) return const {0, 1, 2};
  return {0, turnoverDayMidLabelIndex(n), n - 1};
}

/// Middle label bar for 3-label day charts: the exact centre bar when the
/// count is odd, else the left bar of the centre pair (see
/// [turnoverDayMidLabelShiftsHalfBar]).
int turnoverDayMidLabelIndex(int barCount) => (barCount - 1) ~/ 2;

/// Even bar counts have no centre bar: the middle label is drawn half a bar
/// pitch to the right of [turnoverDayMidLabelIndex] so it sits at the exact
/// horizontal centre and both gaps look equal.
bool turnoverDayMidLabelShiftsHalfBar(int barCount) =>
    barCount > 3 && barCount.isEven;

/// Visible x-axis label indices for displayed [buckets] (one bar per bucket).
///
/// Day grain: always **exactly 3** labels (first / middle / last) when ≥3 bars.
/// Month/year: fixed step; >24 months: ends + January year anchors.
Set<int> turnoverAxisLabelIndices({
  List<DateTime>? buckets,
  int? barCount,
  required TurnoverAxisGrain grain,
  DateTime? rangeStart,
  DateTime? rangeEnd,
  double? chartInnerWidth,
  String locale = 'en',
  TextStyle labelStyle = const TextStyle(
    fontSize: 7,
    fontWeight: FontWeight.w600,
  ),
  double labelGap = 8,
  TurnoverPeriod? period,
}) {
  final list = buckets ??
      [
        for (var i = 0; i < (barCount ?? 0); i++)
          DateTime(2000, 1, 1 + i),
      ];
  final n = list.length;
  if (n <= 0) return const <int>{};
  if (n == 1) return const {0};
  if (n == 2) return const {0, 1};

  final rs = _d(rangeStart ?? list.first);
  final re = _d(rangeEnd ?? list.last);
  final last = n - 1;

  // Client: day views (2w / 1m / any day range) — every date when they all
  // fit, otherwise exactly three: first, middle, last.
  if (grain == TurnoverAxisGrain.day) {
    var widest = 0.0;
    for (final b in list) {
      final w = turnoverMeasureLabelWidth(
        turnoverAxisBarLabel(
          bucket: b,
          grain: grain,
          isFirstLabel: false,
          rangeStart: rs,
          rangeEnd: re,
          locale: locale,
        ),
        labelStyle,
      );
      if (w > widest) widest = w;
    }
    final s0 = turnoverMinFitStep(
      barCount: n,
      plotWidth: chartInnerWidth ?? 280,
      labelWidth: widest,
    );
    if (s0 <= 1) return {for (var i = 0; i < n; i++) i};
    return turnoverDayThreeLabelIndices(n);
  }
  final needYears = grain == TurnoverAxisGrain.month &&
      turnoverMonthLabelsNeedYears(
        rangeStart: rs,
        rangeEnd: re,
        period: period,
      );

  if (needYears) {
    // Year-only labels (>24 months): one label per year on its January bar,
    // so every gap is exactly 12 bars (equal on screen). Each year once.
    // Thinned to every k-th year with the same constant step when needed.
    final jans = <int>[
      for (var i = 0; i < n; i++)
        if (list[i].month == DateTime.january) i,
    ];
    if (jans.isEmpty) return {last};
    final pitch = turnoverBarPitch(
      plotWidth: chartInnerWidth ?? 280,
      barCount: n,
    );
    final yearW = turnoverMeasureLabelWidth('2026', labelStyle);
    final k = math.max(1, ((yearW + 5) / (12 * pitch)).ceil());
    return {for (var i = 0; i < jans.length; i += k) jans[i]};
  }

  // Day / month (≤24) / year: every bar labelled when the real labels fit at
  // the current size, else one even step with first + last always labelled.
  var widest = 0.0;
  for (final b in list) {
    final text = turnoverAxisBarLabel(
      bucket: b,
      grain: grain,
      isFirstLabel: false,
      rangeStart: rs,
      rangeEnd: re,
      locale: locale,
    );
    final w = turnoverMeasureLabelWidth(text, labelStyle);
    if (w > widest) widest = w;
  }
  return turnoverEvenLabelIndices(
    barCount: n,
    plotWidth: chartInnerWidth ?? 280,
    labelWidth: widest,
  );
}

/// Bar-centre pitch under [BarChartAlignment.spaceEvenly] — conservative
/// lower bound (`plot / (n + 1)`), so labels picked with it never overlap.
double turnoverBarPitch({required double plotWidth, required int barCount}) {
  if (barCount <= 0) return plotWidth;
  return plotWidth / (barCount + 1);
}

/// Smallest bar-index step at which labels of [labelWidth] (+ [minGap]) do
/// not touch.
int turnoverMinFitStep({
  required int barCount,
  required double plotWidth,
  required double labelWidth,
  double minGap = 5,
}) {
  final pitch = turnoverBarPitch(plotWidth: plotWidth, barCount: barCount);
  if (pitch <= 0) return math.max(1, barCount - 1);
  return math.max(1, ((labelWidth + minGap) / pitch).ceil());
}

/// Evenly spaced x-label indices.
///
/// - Every bar when the labels fit (e.g. 1y = 12 month labels).
/// - Otherwise the smallest step ≥ the fit step that divides the span exactly
///   (perfectly even, first + last labelled).
/// - If no such step exists (prime span), keep the even grid from the first
///   bar and drop the grid label that would collide with the last bar; the
///   last bar is always labelled and no label is ever closer than one step.
Set<int> turnoverEvenLabelIndices({
  required int barCount,
  required double plotWidth,
  required double labelWidth,
  double minGap = 5,
}) {
  final n = barCount;
  if (n <= 0) return const <int>{};
  if (n == 1) return const {0};
  final last = n - 1;
  final s0 = turnoverMinFitStep(
    barCount: n,
    plotWidth: plotWidth,
    labelWidth: labelWidth,
    minGap: minGap,
  );
  if (s0 <= 1) return {for (var i = 0; i < n; i++) i};
  if (s0 > last) return {last};
  // Exactly equal gaps everywhere (client): labels sit on a constant step
  // counted back from the last bar, so the last bar is always labelled. The
  // first bar is labelled too when the step divides the span; otherwise the
  // grid starts on bar `last % s` (< s) and no shorter / longer gap exists.
  // Pick the step (s0…2·s0) with the smallest start offset, preferring an
  // exact divisor, then more labels.
  var bestS = s0;
  var bestR = 1 << 30;
  final maxS = math.min(last, s0 * 2);
  for (var s = s0; s <= maxS; s++) {
    final r = last % s;
    if (r < bestR) {
      bestR = r;
      bestS = s;
    }
    if (r == 0) break;
  }
  return {for (var i = bestR; i <= last; i += bestS) i};
}

/// Label indices with a constant [step] counted back from the **last** bar, so
/// the last bar always has its label, plus the first bar. Any label closer
/// than [step] to the first one is dropped so the two never collide. Works for
/// every bar count (no prime-span fallback to "ends only").
Set<int> turnoverEndAnchoredLabelIndices({
  required int barCount,
  required int step,
}) {
  final n = barCount;
  if (n <= 0) return const <int>{};
  if (n == 1) return const {0};
  if (n == 2) return const {0, 1};
  final last = n - 1;
  final s = step.clamp(1, last);
  final out = <int>{0, last};
  for (var i = last - s; i > 0; i -= s) {
    if (i >= s) out.add(i);
  }
  return out;
}

/// Nice Y-axis scale: equal intervals from data range, capped by [maxIntervals]
/// and by vertical space so labels never collide.
class TurnoverYAxisScale {
  const TurnoverYAxisScale({
    required this.maxY,
    required this.interval,
    required this.tickCount,
  });

  final double maxY;
  final double interval;

  /// Number of intervals from 0 → [maxY] (tick labels at interval…maxY).
  final int tickCount;
}

/// Round [value] up to 1 / 2 / 5 × 10^n.
double turnoverNiceCeil(double value) {
  if (value <= 0 || value.isNaN || value.isInfinite) return 1;
  final exp = (math.log(value) / math.ln10).floor();
  final frac = value / math.pow(10, exp);
  final niceFrac = frac <= 1
      ? 1.0
      : frac <= 2
          ? 2.0
          : frac <= 5
              ? 5.0
              : 10.0;
  return niceFrac * math.pow(10, exp);
}

/// Format a Y-axis money tick (compact; no currency symbol).
String turnoverYAxisLabel(double v) {
  if (v <= 0) return '0';
  if (v >= 1000000) {
    final m = v / 1000000;
    final s = m == m.roundToDouble()
        ? m.toInt().toString()
        : m.toStringAsFixed(1);
    return '${s}M';
  }
  if (v >= 1000) {
    final k = v / 1000;
    final s = k == k.roundToDouble()
        ? k.toInt().toString()
        : k.toStringAsFixed(1);
    return '${s}k';
  }
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

/// Build an equal-interval Y scale for [peak] bar value.
///
/// [plotHeight] limits how many labels fit (font + gap). [maxIntervals] is a
/// hard cap (default 5).
TurnoverYAxisScale turnoverYAxisScale({
  required double peak,
  required double plotHeight,
  int maxIntervals = 5,
  double labelHeight = 12,
  double labelGap = 6,
}) {
  final rawMax = peak <= 0 ? 1.0 : peak * 1.15;
  final bySpace = plotHeight <= 0
      ? 2
      : math.max(2, (plotHeight / (labelHeight + labelGap)).floor());
  final intervals = math.min(maxIntervals, bySpace).clamp(2, maxIntervals);

  final roughStep = rawMax / intervals;
  final interval = turnoverNiceCeil(roughStep);
  final tickCount = math.max(1, (rawMax / interval).ceil());
  final maxY = interval * tickCount;
  return TurnoverYAxisScale(
    maxY: maxY,
    interval: interval,
    tickCount: tickCount,
  );
}

/// Left-axis reserved width from the widest tick label + padding.
double turnoverYAxisReservedSize({
  required TurnoverYAxisScale scale,
  required TextStyle labelStyle,
  double padding = 8,
  double minSize = 28,
  double maxSize = 56,
}) {
  var maxW = 0.0;
  for (var i = 1; i <= scale.tickCount; i++) {
    final w = turnoverMeasureLabelWidth(
      turnoverYAxisLabel(scale.interval * i),
      labelStyle,
    );
    if (w > maxW) maxW = w;
  }
  final needed = maxW + padding;
  if (needed < minSize) return minSize;
  if (needed > maxSize) return maxSize;
  return needed;
}

/// One x-axis label placed in plot coordinates.
class TurnoverAxisLabelSlot {
  const TurnoverAxisLabelSlot({
    required this.barIndex,
    required this.text,
    required this.left,
    required this.width,
  });

  /// Bar whose date the label shows (nearest bar to the label position).
  final int barIndex;
  final String text;

  /// Left edge of the label box, in the same x space as the plot edges.
  final double left;
  final double width;

  double get center => left + width / 2;
  double get right => left + width;
}

/// Bar centre x for bar [index] under fl_chart `BarChartAlignment.spaceEvenly`
/// inside a plot from [plotLeft] of width [plotWidth].
double turnoverBarCenterX({
  required int index,
  required int barCount,
  required double plotLeft,
  required double plotWidth,
  required double barWidth,
}) {
  final each = (plotWidth - barCount * barWidth) / (barCount + 1);
  return plotLeft + each * (index + 1) + barWidth * index + barWidth / 2;
}

/// Client x-axis layout. Every label sits under the bar whose date it shows.
///
/// - Every bar labelled (3m, 6m, 1y, short day ranges): each label centred on
///   its own bar; only the first / last are nudged inward just enough not to
///   cross [plotLeft] / [plotRight].
/// - Only some bars labelled (2w, 1m, 2y, All): first bar's label flush left,
///   last bar's label flush right (each still covers its bar).
///   - Day grain: exactly 3 labels; the middle one is centred on the plot
///     centre and shows the bar there (odd count: exactly that bar; even: one
///     of the two centre bars, which the label still covers).
///   - Other grains: labels on an (almost) constant bar step from first to
///     last, each centred on its bar; steps never mix 1 and 2 bars.
/// - [distinctTexts] (year-only views): never repeat a label text.
/// - Labels never overlap (≥ [minGap] between boxes) or cross the plot edges.
List<TurnoverAxisLabelSlot> turnoverAxisLabelLayout({
  required double plotLeft,
  required double plotRight,
  required List<double> barCenters,
  required List<String> texts,
  required List<double> widths,
  required TurnoverAxisGrain grain,
  bool distinctTexts = false,
  double minGap = 4,
}) {
  final n = barCenters.length;
  if (n == 0) return const [];

  double clampLeft(double left, double w) =>
      left.clamp(plotLeft, math.max(plotLeft, plotRight - w)).toDouble();

  TurnoverAxisLabelSlot slot(int bar, double left) => TurnoverAxisLabelSlot(
        barIndex: bar,
        text: texts[bar],
        left: clampLeft(left, widths[bar]),
        width: widths[bar],
      );

  /// Centred on own bars (ends clamped inside the plot).
  List<TurnoverAxisLabelSlot> underBars(List<int> idx, {bool flushEnds = false}) {
    return [
      for (var j = 0; j < idx.length; j++)
        if (flushEnds && j == 0 && idx.length > 1)
          slot(idx[j], plotLeft)
        else if (flushEnds && j == idx.length - 1 && idx.length > 1)
          slot(idx[j], plotRight - widths[idx[j]])
        else
          slot(idx[j], barCenters[idx[j]] - widths[idx[j]] / 2),
    ];
  }

  bool ok(List<TurnoverAxisLabelSlot> s) {
    for (var j = 1; j < s.length; j++) {
      if (s[j].left - s[j - 1].right < minGap - 1e-9) return false;
      if (s[j].barIndex <= s[j - 1].barIndex) return false;
    }
    if (distinctTexts && s.map((e) => e.text).toSet().length != s.length) {
      return false;
    }
    return true;
  }

  if (n == 1) return underBars([0]);

  // 1) Every bar labelled, each under its own bar.
  final all = underBars([for (var i = 0; i < n; i++) i]);
  if (ok(all)) return all;

  // 2) Day views: exactly 3 (first / centre / last).
  if (grain == TurnoverAxisGrain.day && n >= 3) {
    final centre = (plotLeft + plotRight) / 2;
    var mid = 0;
    var bestD = double.infinity;
    for (var j = 1; j < n - 1; j++) {
      final d = (barCenters[j] - centre).abs();
      if (d < bestD - 1e-9) {
        bestD = d;
        mid = j;
      }
    }
    final three = [
      slot(0, plotLeft),
      slot(mid, centre - widths[mid] / 2),
      slot(n - 1, plotRight - widths[n - 1]),
    ];
    if (ok(three)) return three;
  }

  // 3) Some bars: first + last + an (almost) constant step between them.
  final last = n - 1;
  for (var k = n - 1; k >= 3; k--) {
    final step = last / (k - 1);
    // Never mix 1- and 2-bar steps (looks random); exact steps are fine.
    if (step < 2 && (last % (k - 1)) != 0) continue;
    final idx = <int>[
      for (var j = 0; j < k; j++) (j * step).round(),
    ];
    final s = underBars(idx, flushEnds: true);
    if (ok(s)) return s;
  }
  final two = underBars([0, last], flushEnds: true);
  if (ok(two)) return two;
  return underBars([last], flushEnds: true);
}

// ---------------------------------------------------------------------------
// v11 (client): one bar per unit again (day ≤ 62 days, month ≤ 60 months,
// year beyond) — NO merging. Labels go on a subset of bars.
// ---------------------------------------------------------------------------

/// Which bars carry an x-label (bar indices, ascending).
///
/// - First bar (range start) and last bar (range end) are ALWAYS labelled.
/// - Labels never overlap: neighbouring labels are ≥ `labelWidth + minGap`
///   apart (centre to centre) at bar [pitch].
/// - Every bar labelled when they fit.
/// - Otherwise an exact step k with (N-1) % k == 0 (perfectly equal gaps) when
///   that shows ≥ 50 % of the labels that fit (equal spacing first); else
///   near-equal positions
///   round(j·(N-1)/(L-1)) — gaps differ by at most one bar (never mixing
///   1- and 2-bar gaps). This happens when N-1 has no usable divisor (e.g.
///   prime), and is the only way to keep both end dates.
/// - [distinctTexts] (year-only views): no label text repeats.
/// Label budget for [fit] labels that physically fit without overlap.
const int kTurnoverMaxAxisLabels = 7;
int turnoverLabelCap(int fit) {
  if (fit < 8) return math.max(2, fit);
  return math.min(kTurnoverMaxAxisLabels, fit - 1);
}

List<int> turnoverUnitLabelBars({
  required int barCount,
  required double pitch,
  required double labelWidth,
  double minGap = 5,
  List<String>? texts,
  bool distinctTexts = false,
}) {
  final n = barCount;
  if (n <= 1) return const [0];
  final last = n - 1;
  final need = labelWidth + minGap;
  final kMin = pitch <= 0 ? last : math.max(1, (need / pitch - 1e-9).ceil());

  bool ok(List<int> idx) {
    if (!distinctTexts || texts == null) return true;
    final t = [for (final i in idx) texts[i]];
    return t.toSet().length == t.length;
  }

  // Client: "if 8 could fit just show 7 or 6" → when 8+ labels fit, use at
  // most min(7, fit − 1); fewer than 8 fitting labels are kept as they are.
  final cap = turnoverLabelCap(kMin <= 1 ? n : last ~/ kMin + 1);

  if (kMin <= 1 && n <= cap) {
    final all = [for (var i = 0; i < n; i++) i];
    if (ok(all)) return all;
  }

  List<int>? exact;
  for (var k = math.max(1, kMin); k <= last; k++) {
    if (last % k != 0) continue;
    if (last ~/ k + 1 > cap) continue;
    final idx = [for (var i = 0; i <= last; i += k) i];
    if (ok(idx)) {
      exact = idx;
      break;
    }
  }

  List<int>? near;
  for (var l = math.min(cap, last ~/ math.max(1, kMin) + 1); l >= 2; l--) {
    final step = last / (l - 1);
    if (step.floor() < kMin) continue;
    if (step < 2 && last % (l - 1) != 0) continue;
    final idx = <int>[for (var j = 0; j < l; j++) (j * step).round()];
    if (ok(idx)) {
      near = idx;
      break;
    }
  }

  // Ends-only (2 labels) never beats a near-equal set with inner labels.
  if (exact != null &&
      (near == null ||
          (exact.length >= near.length * 0.5 &&
              (exact.length >= 3 || near.length <= 2)))) {
    return exact;
  }
  return near ?? exact ?? [0, last];
}

/// Bar geometry for `BarChartAlignment.center`: bar centres run from
/// plotLeft + edge/2 to plotRight − edge/2 ([edge] = widest label), so
/// centred end labels just fit inside the plot.
class TurnoverBarGeometry {
  const TurnoverBarGeometry({
    required this.plotWidth,
    required this.barCount,
    required this.edge,
    required this.barWidth,
  });

  final double plotWidth;
  final int barCount;
  final double edge;
  final double barWidth;

  double get pitch =>
      barCount <= 1 ? 0 : (plotWidth - edge) / (barCount - 1);

  /// Space between bars for fl_chart `groupsSpace`.
  double get groupsSpace => math.max(0, pitch - barWidth);

  /// Bar centre x relative to the plot's left edge.
  double centerX(int j) =>
      barCount <= 1 ? plotWidth / 2 : edge / 2 + j * pitch;

  int nearestBar(double localX) {
    if (barCount <= 1) return 0;
    return ((localX - edge / 2) / pitch).round().clamp(0, barCount - 1);
  }
}

/// Bar width: ≤ [maxBarWidth], always leaving ≥ [minGap] (and ~30 %) gap.
double turnoverPlannedBarWidth({
  required double pitch,
  required double maxBarWidth,
  double minGap = 2.5,
}) {
  if (pitch <= 0) return maxBarWidth;
  final gap = math.max(minGap, pitch * 0.3);
  return (pitch - gap).clamp(1.0, maxBarWidth).toDouble();
}
