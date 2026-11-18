import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/inventory/presentation/item_list_tools.dart';
import 'package:inventory_app/features/turnover/turnover_averages.dart';
import 'package:inventory_app/features/turnover/turnover_money.dart';
import 'package:inventory_app/features/turnover/turnover_period.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/scroll_chrome.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

enum TurnoverSortKey { name, amount, recent }

typedef TurnoverRowKey = ({String title, int revenueCents, DateTime lastSaleAt});

/// Sold-items order within a month: A–Z (Z–A when reversed), highest /
/// lowest amount, most recent / oldest.
int compareTurnoverRows(
  SortState<TurnoverSortKey> sort,
  TurnoverRowKey a,
  TurnoverRowKey b,
) {
  final descending = !sort.reversed;
  switch (sort.key) {
    case TurnoverSortKey.name:
      final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return sort.reversed ? -c : c;
    case TurnoverSortKey.recent:
      return descending
          ? b.lastSaleAt.compareTo(a.lastSaleAt)
          : a.lastSaleAt.compareTo(b.lastSaleAt);
    case TurnoverSortKey.amount:
      return descending
          ? b.revenueCents.compareTo(a.revenueCents)
          : a.revenueCents.compareTo(b.revenueCents);
  }
}

const _kDefaultTurnoverSort = SortState<TurnoverSortKey>(
  TurnoverSortKey.amount,
);

class _TurnoverItemAgg {
  const _TurnoverItemAgg({
    required this.itemId,
    required this.title,
    required this.quantity,
    required this.revenueCents,
    required this.unitPrice,
    required this.lastSaleAt,
    this.unit,
  });

  final String itemId;
  final String title;
  final String? unit;
  final double unitPrice;
  final double quantity;
  /// Revenue in integer cents (cent-safe sums).
  final int revenueCents;
  final DateTime lastSaleAt;

  double get revenue => centsToMoney(revenueCents);
}

class TurnoverPage extends ConsumerStatefulWidget {
  const TurnoverPage({super.key});

  @override
  ConsumerState<TurnoverPage> createState() => _TurnoverPageState();
}

class _TurnoverPageState extends ConsumerState<TurnoverPage> {
  /// Collapsed Year ('y2026') / Month ('m2026-10') headers of the sold list
  /// (same behavior as the customer purchase history).
  final Set<String> _collapsedSold = {};

  void _toggleSold(String key) => setState(() {
        if (!_collapsedSold.remove(key)) _collapsedSold.add(key);
      });

  TurnoverPeriod _period = TurnoverPeriod.m1;
  SortState<TurnoverSortKey> _sort = _kDefaultTurnoverSort;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _categoryFilter;

  /// Slider thumbs (0–1). After a chip tap the thumbs show period/data
  /// fraction at the end; the chart still uses the chip calendar window
  /// until the user drags the slider ([_sliderOverridesChip]).
  RangeValues _slider = const RangeValues(0, 1);
  bool get _usingCustomRange => _customFrom != null || _customTo != null;
  bool _showSearch = false;
  final _search = TextEditingController();

  /// After sales first load, apply default chip (1m) onto the slider once.
  bool _initialPeriodSliderApplied = false;

  /// When false, chips drive the chart from calendar period bounds (empty
  /// months before first sale stay visible). When true (user dragged the
  /// slider), the thumbs map across first-sale→today.
  bool _sliderOverridesChip = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  RangeValues _sliderFromDateWindow({
    required DateTime from,
    required DateTime to,
    required DateTime timelineStart,
    required DateTime timelineEnd,
  }) {
    // Calendar-day indices (same mapping as _effectiveRange), DST-safe.
    final lastIdx =
        calendarDaysInclusive(timelineStart, timelineEnd) - 1;
    if (lastIdx <= 0) return const RangeValues(0, 1);
    double idx(DateTime d) =>
        d.isBefore(timelineStart)
            ? 0
            : (calendarDaysInclusive(timelineStart, d) - 1).toDouble();
    final start = idx(from) / lastIdx;
    final end = idx(to) / lastIdx;
    return RangeValues(
      start.clamp(0.0, 1.0),
      end.clamp(0.0, 1.0),
    );
  }

  (DateTime, DateTime) _periodBounds() =>
      turnoverPeriodBounds(_period, DateTime.now());

  /// Min/max sale timestamps in [sales], or `null` if empty.
  (DateTime, DateTime)? _saleDataBounds(List<Sale> sales) {
    if (sales.isEmpty) return null;
    var min = sales.first.createdAt;
    var max = sales.first.createdAt;
    for (final s in sales) {
      if (s.createdAt.isBefore(min)) min = s.createdAt;
      if (s.createdAt.isAfter(max)) max = s.createdAt;
    }
    return (min, max);
  }

  /// Full slider timeline: first sale → today (chips end at "now").
  int _timelineDays(DateTime? dataFrom) {
    if (dataFrom == null) return 0;
    return calendarDaysInclusive(
      startOfDay(dataFrom),
      startOfDay(DateTime.now()),
    );
  }

  RangeValues _sliderForPeriod(TurnoverPeriod period, int timelineDays) {
    final unit = turnoverPeriodSliderUnitRange(
      period: period,
      timelineDays: timelineDays,
      now: DateTime.now(),
    );
    return RangeValues(unit.$1, unit.$2);
  }

  /// Visible filter window.
  ///
  /// - Chip (not dragged): **calendar** period bounds (2y keeps empty months).
  /// - Slider thumbs still show periodDays/dataDays at the end (visual).
  /// - After the user drags the slider (or All): map thumbs over
  ///   first-sale→today.
  (DateTime?, DateTime?) _effectiveRange({DateTime? dataFrom, DateTime? dataTo}) {
    if (_usingCustomRange) {
      return (
        _customFrom != null ? startOfDay(_customFrom!) : null,
        _customTo != null ? endOfDay(_customTo!) : null,
      );
    }

    final now = DateTime.now();

    // Chips: locked to calendar window until the user scrubs the slider.
    if (_period != TurnoverPeriod.all && !_sliderOverridesChip) {
      final bounds = _periodBounds();
      return (bounds.$1, bounds.$2);
    }

    // All, or scrubbing: slider maps the real data timeline.
    if (dataFrom == null) {
      if (_period == TurnoverPeriod.all) return (null, null);
      final bounds = _periodBounds();
      return (bounds.$1, bounds.$2);
    }
    final boundsFrom = startOfDay(dataFrom);
    final end = (dataTo != null && dataTo.isAfter(now)) ? dataTo : now;
    final boundsTo = endOfDay(end);

    final sliderFull = _slider.start <= 0.001 && _slider.end >= 0.999;
    if (sliderFull) return (boundsFrom, boundsTo);

    // Map thumbs on inclusive calendar days (not ms) so the last day bar
    // always matches the selected end date (no DST / off-by-one drift).
    final dayCount = calendarDaysInclusive(boundsFrom, startOfDay(boundsTo));
    if (dayCount <= 1) return (boundsFrom, boundsTo);
    final lastIdx = dayCount - 1;
    final fromIdx = (_slider.start * lastIdx).round().clamp(0, lastIdx);
    final toIdx = (_slider.end * lastIdx).round().clamp(fromIdx, lastIdx);
    final from = addCalendarDays(boundsFrom, fromIdx);
    final to = addCalendarDays(boundsFrom, toIdx);
    return (startOfDay(from), endOfDay(to));
  }

  bool _saleInRange(Sale sale, DateTime? from, DateTime? to) {
    final at = sale.createdAt;
    if (from != null && at.isBefore(from)) return false;
    if (to != null && at.isAfter(to)) return false;
    return true;
  }

  void _selectPeriod(TurnoverPeriod period) {
    final sales = ref.read(salesProvider).valueOrNull ?? const <Sale>[];
    final dataFrom = _saleDataBounds(sales)?.$1;
    final timelineDays = _timelineDays(dataFrom);
    setState(() {
      _period = period;
      _customFrom = null;
      _customTo = null;
      // Visual fraction of data; chart uses calendar bounds until scrubbed.
      // All already maps via `_period == all` in `_effectiveRange` — do NOT
      // set `_sliderOverridesChip` here or the All chip never stays selected.
      _slider = _sliderForPeriod(period, timelineDays);
      _sliderOverridesChip = false;
      _initialPeriodSliderApplied = true;
    });
  }

  int _dataSpanDays(List<Sale> allSales) {
    if (allSales.isEmpty) return 0;
    var min = allSales.first.createdAt;
    var max = allSales.first.createdAt;
    for (final s in allSales) {
      if (s.createdAt.isBefore(min)) min = s.createdAt;
      if (s.createdAt.isAfter(max)) max = s.createdAt;
    }
    return max.difference(min).inDays;
  }

  String _fmtShort(DateTime d) => formatDateShort(d, ref.read(tProvider).code);

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    final picked = await showSortSheet<TurnoverSortKey>(
      context: context,
      options: [
        SortOption(
          key: TurnoverSortKey.name,
          icon: Icons.sort_by_alpha_rounded,
          label: t('sort_name_az'),
          reversedLabel: t('sort_name_za'),
        ),
        SortOption(
          key: TurnoverSortKey.amount,
          icon: Icons.payments_rounded,
          label: t('sort_highest_amount'),
          reversedLabel: t('sort_lowest_amount'),
        ),
        SortOption(
          key: TurnoverSortKey.recent,
          icon: Icons.schedule_rounded,
          label: t('sort_most_recent'),
          reversedLabel: t('sort_oldest'),
        ),
      ],
      current: _sort,
      defaultState: _kDefaultTurnoverSort,
    );
    if (picked != null && mounted && picked != _sort) {
      setState(() => _sort = picked);
    }
  }

  Future<void> _showFilterSheet() async {
    final t = ref.read(tProvider);
    // Only categories that still exist on inventory items.
    final categories = usedCategories(
      ref.read(categoriesProvider).valueOrNull ?? <Category>[],
      ref.read(inventoryItemsProvider).valueOrNull ?? <InventoryItem>[],
    );
    final sales = ref.read(salesProvider).valueOrNull ?? const <Sale>[];
    final cashBounds = _saleDataBounds(sales);
    // Calendar: earliest sale day → today. Today is always offered (the
    // current day is always the last date, even with 0 turnover).
    final today = startOfDay(DateTime.now());
    final cashFirst = cashBounds != null ? startOfDay(cashBounds.$1) : null;
    final saleLast = cashBounds != null ? startOfDay(cashBounds.$2) : today;
    final cashLast = saleLast.isAfter(today) ? saleLast : today;
    var from = _customFrom;
    var to = _customTo;
    var category = categories.any((c) => c.id == _categoryFilter)
        ? _categoryFilter
        : null;

    final applied = await showAppSheet<bool>(
      context: context,
      alignTop: true,
      heightFactor: 0.6,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          Future<void> pick(bool isFrom) async {
            // No cashflow yet — keep pickers safe (today only).
            final first = cashFirst ?? startOfDay(DateTime.now());
            final last = cashLast;
            if (isFrom) {
              // Leave room for To = From+1 when history spans ≥2 days.
              final fromLast = last.isAfter(first)
                  ? addCalendarDays(last, -1)
                  : first;
              final d = await pickFilterDate(
                context,
                from,
                firstDate: first,
                lastDate: fromLast,
              );
              if (d == null) return;
              setModal(() {
                from = startOfDay(d);
                // Always snap To to From+1 calendar day; user may raise To later.
                final minTo = addCalendarDays(from!, 1);
                to = minTo.isAfter(last) ? last : minTo;
                if (!to!.isAfter(from!)) {
                  // Single-day history: only one selectable calendar day.
                  to = last.isAfter(from!) ? last : from;
                }
              });
              return;
            }
            final minTo = from != null
                ? addCalendarDays(from!, 1)
                : first;
            final toFirst = minTo.isAfter(last) ? last : minTo;
            final d = await pickFilterDate(
              context,
              to,
              firstDate: toFirst,
              lastDate: last.isBefore(toFirst) ? toFirst : last,
            );
            if (d == null) return;
            setModal(() => to = startOfDay(d));
          }

          return AppFilterSheet(
            onReset: () {
              from = null;
              to = null;
              category = null;
              Navigator.pop(ctx, true);
            },
            onApply: () => Navigator.pop(ctx, true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppFilterDateField(
                        placeholder: t('from_date'),
                        value: from,
                        onTap: () => pick(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppFilterDateField(
                        placeholder: t('to_date'),
                        value: to,
                        onTap: () => pick(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppCategoryDropdown(
                  categories: categories,
                  value: category,
                  onChanged: (v) => setModal(() => category = v),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (applied == true && mounted) {
      final timelineDays = _timelineDays(cashFirst);
      final now = DateTime.now();
      setState(() {
        final cleared = from == null && to == null;
        _customFrom = from;
        _customTo = to;
        _categoryFilter = category;
        if (cleared) {
          _slider = _sliderForPeriod(_period, timelineDays);
          _sliderOverridesChip = false;
        } else if (from != null && to != null && cashFirst != null) {
          // Keep scrollbar visible — mirror the filter onto the track.
          final timelineEnd = endOfDay(
            cashLast.isAfter(now) ? cashLast : now,
          );
          _slider = _sliderFromDateWindow(
            from: startOfDay(from!),
            to: endOfDay(to!),
            timelineStart: cashFirst,
            timelineEnd: timelineEnd,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );
    final salesAsync = ref.watch(salesProvider);
    final inventoryAsync = ref.watch(inventoryItemsProvider);
    // Slider timeline = first sale → today (chips preset a trailing window).
    final dataBounds = _saleDataBounds(salesAsync.valueOrNull ?? const []);
    final timelineDays = _timelineDays(dataBounds?.$1);
    if (!_initialPeriodSliderApplied &&
        !_usingCustomRange &&
        timelineDays > 0) {
      _initialPeriodSliderApplied = true;
      final preset = _sliderForPeriod(_period, timelineDays);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _usingCustomRange) return;
        setState(() {
          _slider = preset;
          _sliderOverridesChip = false;
        });
      });
    }
    final range = _effectiveRange(
      dataFrom: dataBounds?.$1,
      dataTo: dataBounds?.$2,
    );

    return ScrollChromeHost(
      scrollTopHeroTag: 'scroll_top_turnover',
      builder: (context, chrome) {
        return CustomScrollView(
          controller: chrome.scrollController,
          physics: kScrollChromePhysics,
          slivers: [
            ...ScrollChrome.headerSlivers(
              context: context,
              chrome: chrome,
              header: (_) => ClientHeader(
                section: 2,
                title: t('turnover'),
                titleAsset: AppAssets.turnover,
                showListActions: false,
                includeTopSafeArea: false,
              ),
            ),
            ...salesAsync.when(
                  loading: () => const <Widget>[
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppLoader(),
                    ),
                  ],
                  error: (e, _) => <Widget>[
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('$e')),
                    ),
                  ],
                  data: (allSales) {
                    return inventoryAsync.when(
                      loading: () => const <Widget>[
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: AppLoader(),
                        ),
                      ],
                      error: (e, _) => <Widget>[
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('$e')),
                        ),
                      ],
                      data: (inventory) {
                    final inventoryById = {for (final i in inventory) i.id: i};
                    // Chip enablement uses the full history span (first→last
                    // sale), not the current filter window.
                    final now = DateTime.now();
                    final historySpanDays = _dataSpanDays(allSales);
                    if (!_usingCustomRange &&
                        !turnoverPeriodFits(
                          period: _period,
                          spanDays: historySpanDays,
                          now: now,
                        )) {
                      // Selected chip longer than data — fall back to All.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted || _usingCustomRange) return;
                        if (turnoverPeriodFits(
                          period: _period,
                          spanDays: historySpanDays,
                          now: DateTime.now(),
                        )) {
                          return;
                        }
                        _selectPeriod(TurnoverPeriod.all);
                      });
                    }

                    final sales = allSales
                        .where((s) => _saleInRange(s, range.$1, range.$2))
                        .toList();

                    // Span of what is actually shown (slider / custom / chip).
                    final visibleSpanDays = () {
                      if (range.$1 != null && range.$2 != null) {
                        return range.$2!
                            .difference(range.$1!)
                            .inDays
                            .clamp(0, 100000);
                      }
                      return _dataSpanDays(sales);
                    }();
                    // While scrubbing / All / custom dates, ignore short-chip
                    // grain locks — follow 62-day / 60-month rules on the
                    // visible window.
                    final labelPeriod = (_sliderOverridesChip ||
                            _period == TurnoverPeriod.all ||
                            _usingCustomRange)
                        ? TurnoverPeriod.all
                        : _period;
                    final q = _search.text.trim().toLowerCase();

                    bool lineAllowed(SaleLine line) {
                      if (_categoryFilter != null) {
                        final inv = inventoryById[line.itemId];
                        if (inv?.categoryId != _categoryFilter) return false;
                      }
                      if (q.isNotEmpty &&
                          !line.title.toLowerCase().contains(q)) {
                        return false;
                      }
                      return true;
                    }

                    int saleContribCents(Sale s) {
                      var sum = 0;
                      for (final line in s.lines) {
                        if (lineAllowed(line)) {
                          sum += lineTotalCents(
                            unitPrice: line.unitPrice,
                            quantity: line.quantity,
                          );
                        }
                      }
                      return sum;
                    }

                    // Full filter window (not last-sale day): e.g. 1m ends today
                    // even if the last sale was earlier.
                    final periodBounds = _periodBounds();
                    final axisFrom = range.$1 ??
                        (sales.isEmpty
                            ? periodBounds.$1
                            : sales
                                .map((s) => s.createdAt)
                                .reduce((a, b) => a.isBefore(b) ? a : b));
                    final axisTo = range.$2 ?? periodBounds.$2;
                    // Inclusive calendar ends — last bar must match range end
                    // (e.g. timeframe to 1 Nov → last day bar is 1 Nov).
                    final axisRangeStart = startOfDay(axisFrom);
                    final axisRangeEnd = startOfDay(axisTo);
                    final axisGrain = turnoverAxisGrain(
                      period: labelPeriod,
                      spanDays: visibleSpanDays,
                      rangeStart: axisRangeStart,
                      rangeEnd: axisRangeEnd,
                    );

                    // Day-level cents; chart draws every natural grain bar and
                    // thins x-labels to a width-safe consistent count.
                    final dayCents = <String, int>{};
                    for (final s in sales) {
                      final contrib = saleContribCents(s);
                      if (contrib == 0) continue;
                      final key = turnoverDayKey(s.createdAt);
                      dayCents[key] = (dayCents[key] ?? 0) + contrib;
                    }
                    final naturalBuckets = turnoverChartBuckets(
                      from: axisRangeStart,
                      to: axisRangeEnd,
                      grain: axisGrain,
                    );
                    final monthLabelsNeedYears = turnoverMonthLabelsNeedYears(
                      rangeStart: axisRangeStart,
                      rangeEnd: axisRangeEnd,
                      period: labelPeriod,
                    );

                    // Averages over the full filter window (incl. empty days),
                    // using the same filtered line totals as the list/chart
                    // (cent-safe).
                    var filteredTotalCents = 0;
                    for (final s in sales) {
                      filteredTotalCents += saleContribCents(s);
                    }
                    final filteredTotal = centsToMoney(filteredTotalCents);
                    final averages = TurnoverAverages.fromTotal(
                      total: filteredTotal,
                      from: axisFrom,
                      to: axisTo,
                    );
                    final yearAvg = averages.yearAvg;
                    final monthAvg = averages.monthAvg;
                    final dayAvg = averages.dayAvg;

                    Widget buildItemCard(_TurnoverItemAgg item) {
                      final inv = inventoryById[item.itemId];
                      final badge = formatQty(item.quantity);
                      final amountOnly = money
                          .formatAmount(item.unitPrice)
                          .trim();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MediaListCard(
                          // Client: sold items are not tappable — no edit screen.
                          thumb: CardThumb(path: inv?.photoPath, badge: badge),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 10, 12, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                        height: 1.2,
                                        color: p.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    PriceUnitLine(
                                      amount: amountOnly,
                                      symbol: money.symbol,
                                      unit: item.unit,
                                    ),
                                  ],
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: CardTotalLine(
                                      value: money.format(item.revenue),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    List<Widget> soldSections() {
                      // Attribute each line to the sale's calendar month so
                      // October section total == October chart bar.
                      final byYear =
                          <int, Map<int, Map<String, _TurnoverItemAgg>>>{};
                      for (final sale in sales) {
                        for (final line in sale.lines) {
                          if (!lineAllowed(line)) continue;
                          final y = sale.createdAt.year;
                          final m = sale.createdAt.month;
                          final map = byYear
                              .putIfAbsent(y, () => {})
                              .putIfAbsent(m, () => {});
                          final prev = map[line.itemId];
                          final last = prev == null ||
                                  sale.createdAt.isAfter(prev.lastSaleAt)
                              ? sale.createdAt
                              : prev.lastSaleAt;
                          final lineCents = lineTotalCents(
                            unitPrice: line.unitPrice,
                            quantity: line.quantity,
                          );
                          map[line.itemId] = _TurnoverItemAgg(
                            itemId: line.itemId,
                            title: line.title,
                            unit: line.unit,
                            unitPrice: line.unitPrice,
                            quantity: (prev?.quantity ?? 0) + line.quantity,
                            revenueCents:
                                (prev?.revenueCents ?? 0) + lineCents,
                            lastSaleAt: last,
                          );
                        }
                      }
                      if (byYear.isEmpty) {
                        return [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                t('no_sales_period'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: p.textSecondary),
                              ),
                            ),
                          ),
                        ];
                      }

                      int cmp(_TurnoverItemAgg a, _TurnoverItemAgg b) =>
                          compareTurnoverRows(
                            _sort,
                            (
                              title: a.title,
                              revenueCents: a.revenueCents,
                              lastSaleAt: a.lastSaleAt,
                            ),
                            (
                              title: b.title,
                              revenueCents: b.revenueCents,
                              lastSaleAt: b.lastSaleAt,
                            ),
                          );

                      final sortedYears = byYear.keys.toList()
                        ..sort((a, b) => b.compareTo(a));
                      final out = <Widget>[];
                      for (final year in sortedYears) {
                        final months = byYear[year]!;
                        final yearTotalCents = months.values
                            .expand((e) => e.values)
                            .fold<int>(0, (s, i) => s + i.revenueCents);
                        final yearTotal = centsToMoney(yearTotalCents);
                        final yearKey = 'y$year';
                        final yearOpen = !_collapsedSold.contains(yearKey);
                        out.add(
                          SectionHeader(
                            title: '$year',
                            expanded: yearOpen,
                            onToggle: () => _toggleSold(yearKey),
                            trailing: Text(
                              money.format(yearTotal),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: p.neon,
                              ),
                            ),
                          ),
                        );
                        if (!yearOpen) continue;
                        final sortedMonths = months.keys.toList()
                          ..sort((a, b) => b.compareTo(a));
                        for (final month in sortedMonths) {
                          final list = months[month]!.values.toList()
                            ..sort(cmp);
                          final monthTotal = centsToMoney(
                            list.fold<int>(
                              0,
                              (s, i) => s + i.revenueCents,
                            ),
                          );
                          final monthName = DateFormat.MMMM(
                            t.code,
                          ).format(DateTime(year, month));
                          final monthKey = 'm$year-$month';
                          final monthOpen =
                              !_collapsedSold.contains(monthKey);
                          out.add(
                            SectionHeader(
                              title: monthName,
                              expanded: monthOpen,
                              onToggle: () => _toggleSold(monthKey),
                              trailing: Text(
                                money.format(monthTotal),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: p.neon,
                                ),
                              ),
                            ),
                          );
                          if (monthOpen) out.addAll(list.map(buildItemCard));
                        }
                      }
                      return out;
                    }

                    final chartRangeLabel =
                        '${_fmtShort(axisFrom)} - ${_fmtShort(axisTo)}';

                    return <Widget>[SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Text.rich(
                              textAlign: TextAlign.center,
                              TextSpan(
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                children: [
                                  TextSpan(text: t('average_prefix')),
                                  TextSpan(
                                    text: t('turnover'),
                                    style: TextStyle(
                                      color: p.neon,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  TextSpan(text: t('average_suffix')),
                                ],
                              ),
                            ),
                            // Export lives only in Settings (client,
                            // phase 3); keeps the old row height.
                            const SizedBox(
                              width: double.infinity,
                              height: 48,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _AverageStrip(
                          yearLabel: t('period_year'),
                          yearValue: money.format(yearAvg),
                          monthLabel: t('period_month'),
                          monthValue: money.format(monthAvg),
                          dayLabel: t('period_day'),
                          dayValue: money.format(dayAvg),
                        ),
                        const SizedBox(height: 14),
                        AppCard(
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                          child: Column(
                            children: [
                              Text(
                                chartRangeLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: p.textPrimary.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 190,
                                child: () {
                                  if (sales.isEmpty || naturalBuckets.isEmpty) {
                                    return Center(
                                      child: Text(
                                        t('no_sales_period'),
                                        style: TextStyle(
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    );
                                  }
                                  return _TurnoverBarsChart(
                                    dayCents: dayCents,
                                    axisGrain: axisGrain,
                                    rangeStart: axisRangeStart,
                                    rangeEnd: axisRangeEnd,
                                    monthLabelsNeedYears: monthLabelsNeedYears,
                                    locale: t.code,
                                    money: money,
                                    neon: p.neon,
                                    stroke: p.stroke,
                                    textMuted: p.textMuted,
                                    // Reset selection when the visible window
                                    // changes (chip / slider / filter).
                                    selectionResetToken:
                                        '${axisRangeStart.toIso8601String()}|${axisRangeEnd.toIso8601String()}|$axisGrain',
                                  );
                                }(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Equal-width chips that always fit the row in every
                        // language (labels scale down instead of overflowing).
                        Row(
                          children: [
                            for (final (n, e) in [
                              (TurnoverPeriod.w2, t('range_2w')),
                              (TurnoverPeriod.m1, t('range_1m')),
                              (TurnoverPeriod.m3, t('range_3m')),
                              (TurnoverPeriod.m6, t('range_6m')),
                              (TurnoverPeriod.y1, t('range_1y')),
                              (TurnoverPeriod.y2, t('range_2y')),
                              (TurnoverPeriod.all, t('range_all')),
                            ].indexed)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: n == 6 ? 0 : 6,
                                  ),
                                  child: _PeriodChip(
                                    label: e.$2,
                                    // Deselect chips while scrubbing so the UI
                                    // matches the slider-driven window.
                                    selected: !_usingCustomRange &&
                                        !_sliderOverridesChip &&
                                        _period == e.$1,
                                    enabled: turnoverPeriodFits(
                                      period: e.$1,
                                      spanDays: historySpanDays,
                                      now: now,
                                    ),
                                    onTap: () => _selectPeriod(e.$1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // Always keep the scrollbar — including while a custom
                        // date filter is active (client).
                        const SizedBox(height: 2),
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 5,
                            activeTrackColor: p.neon,
                            inactiveTrackColor: p.neon.withValues(
                              alpha: 0.28,
                            ),
                            overlayColor: const Color(
                              0xFFFFD54F,
                            ).withValues(alpha: 0.18),
                            rangeThumbShape: const RoundRangeSliderThumbShape(
                              enabledThumbRadius: 12,
                            ),
                            thumbColor: const Color(0xFFFFD54F),
                            rangeTrackShape:
                                const RoundedRectRangeSliderTrackShape(),
                            // Only the yellow circles — tapping the track must
                            // not jump a thumb (client).
                            thumbSelector: _turnoverThumbsOnlySelector,
                          ),
                          child: RangeSlider(
                            values: _slider,
                            min: 0,
                            max: 1,
                            // ~2-day steps across the cashflow timeline.
                            divisions: math.max(
                              1,
                              (timelineDays / 2).round().clamp(1, 1000),
                            ),
                            onChanged: (v) {
                              AppHaptics.selection();
                              setState(() {
                                // Scrubbing leaves chip lock / custom dates and
                                // maps thumbs across first-sale→today.
                                _customFrom = null;
                                _customTo = null;
                                _sliderOverridesChip = true;
                                _slider = RangeValues(
                                  (v.start).clamp(0.0, v.end),
                                  (v.end).clamp(v.start, 1.0),
                                );
                              });
                            },
                          ),
                        ),
                        ListActionIconsRow(
                          onSort: _showSortSheet,
                          onFilter: _showFilterSheet,
                          onSearch: () =>
                              setState(() => _showSearch = !_showSearch),
                          sortActive: _sort != _kDefaultTurnoverSort,
                          filterActive:
                              _usingCustomRange || _categoryFilter != null,
                          searchActive:
                              _showSearch || _search.text.trim().isNotEmpty,
                        ),
                        if (_showSearch)
                          AppSearchField(
                            controller: _search,
                            hintText: t('search_sold_items'),
                            padding: const EdgeInsets.only(bottom: 10),
                            onChanged: (_) => setState(() {}),
                            onDismiss: () {
                              if (mounted) {
                                setState(() => _showSearch = false);
                              }
                            },
                          ),
                        const SizedBox(height: 4),
                        ...soldSections(),
                      ]),
                    ),
                    )];
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Client: the Year/Month/Day averages are display-only — tapping them must
/// not open the currency picker (currency is changed in Settings).
class _AverageStrip extends StatelessWidget {
  const _AverageStrip({
    required this.yearLabel,
    required this.yearValue,
    required this.monthLabel,
    required this.monthValue,
    required this.dayLabel,
    required this.dayValue,
  });

  final String yearLabel;
  final String yearValue;
  final String monthLabel;
  final String monthValue;
  final String dayLabel;
  final String dayValue;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              const Color(0xFF0B3D1A),
              p.neon.withValues(alpha: 0.55),
              p.neon,
            ],
          ),
          border: Border.all(color: p.neon.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _AvgCell(
                label: yearLabel,
                value: yearValue,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.black.withValues(alpha: 0.25),
              ),
              _AvgCell(
                label: monthLabel,
                value: monthValue,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.black.withValues(alpha: 0.25),
              ),
              _AvgCell(
                label: dayLabel,
                value: dayValue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvgCell extends StatelessWidget {
  const _AvgCell({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFB8FFC0),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive turnover bars.
///
/// Bars = every natural grain bucket (3m→3, 6m→6, 1y→12, 2y→24, 2w→14…).
/// Labels = width-safe evenly spaced subset (same density across chips on the
/// same screen). Touch state stays here so drag does not rebuild the page.
class _TurnoverBarsChart extends StatefulWidget {
  const _TurnoverBarsChart({
    required this.dayCents,
    required this.axisGrain,
    required this.rangeStart,
    required this.rangeEnd,
    required this.monthLabelsNeedYears,
    required this.locale,
    required this.money,
    required this.neon,
    required this.stroke,
    required this.textMuted,
    required this.selectionResetToken,
  });

  final Map<String, int> dayCents;
  final TurnoverAxisGrain axisGrain;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final bool monthLabelsNeedYears;
  final String locale;
  final MoneyFormatter money;
  final Color neon;
  final Color stroke;
  final Color textMuted;
  final String selectionResetToken;

  @override
  State<_TurnoverBarsChart> createState() => _TurnoverBarsChartState();
}

class _TurnoverBarsChartState extends State<_TurnoverBarsChart> {
  int? _touchedBarIndex;

  @override
  void didUpdateWidget(covariant _TurnoverBarsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionResetToken != widget.selectionResetToken) {
      _touchedBarIndex = null;
    }
  }

  void _clearSelection() {
    if (_touchedBarIndex == null) return;
    setState(() => _touchedBarIndex = null);
  }

  TurnoverBarGeometry? _geo;

  void _selectAtPlotX(double localX) {
    final geo = _geo;
    if (geo == null || geo.barCount <= 0) return;
    final idx = geo.nearestBar(localX);
    if (idx != _touchedBarIndex) {
      setState(() => _touchedBarIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    const chartH = 190.0;
    // Single-line x-labels in every view (>24 months = year only, no
    // two-line "Aug\n2026"), so one bottom height fits all.
    const bottomReserved = 28.0;
    final plotH = chartH - bottomReserved;
    final yLabelStyle = TextStyle(
      color: widget.textMuted,
      fontSize: 9,
      fontWeight: FontWeight.w600,
    );
    // Client: day dates use the same x-label size as months and years.
    final labelStyle = TextStyle(
      color: widget.textMuted,
      fontSize: 7,
      fontWeight: FontWeight.w600,
    );
    // Provisional end inset from a sample label (refined after real labels).
    final endLabelSample = switch (widget.axisGrain) {
      TurnoverAxisGrain.day => '28. Nov',
      TurnoverAxisGrain.month =>
        widget.monthLabelsNeedYears ? '2026' : 'Nov',
      TurnoverAxisGrain.year => '2026',
    };
    final sampleW = turnoverMeasureLabelWidth(endLabelSample, labelStyle);
    var leftInset = turnoverEndLabelInset(sampleW);
    var rightInset = turnoverRightLabelInset(sampleW);

    return LayoutBuilder(
      builder: (context, chartBox) {
        final chartW = chartBox.maxWidth;
        final provisionalY = turnoverYAxisReservedSize(
          scale: const TurnoverYAxisScale(
            maxY: 1,
            interval: 1,
            tickCount: 2,
          ),
          labelStyle: yLabelStyle,
        );

        final natural = turnoverChartBuckets(
          from: widget.rangeStart,
          to: widget.rangeEnd,
          grain: widget.axisGrain,
        );
        if (natural.isEmpty) {
          return const SizedBox.shrink();
        }

        // v11 (client): one bar per day / month / year again — no merging.
        // Labels sit centred under a subset of bars; the first bar (range
        // start) and last bar (range end) are always labelled. End labels stay
        // centred on their bars: bar centres start half a label in from each
        // plot edge, so nothing is cut off.
        leftInset = 4;
        rightInset = 4;
        final axisStyle = DefaultTextStyle.of(context).style.merge(labelStyle);
        final naturalTexts = <String>[
          for (final d in natural)
            turnoverAxisBarLabel(
              bucket: d,
              grain: widget.axisGrain,
              isFirstLabel: false,
              rangeStart: widget.rangeStart,
              rangeEnd: widget.rangeEnd,
              locale: widget.locale,
              monthLabelsNeedYears: widget.monthLabelsNeedYears,
            ),
        ];
        // +1: rounding headroom so a label never touches the plot edge.
        final edgeW = [
              for (final t in naturalTexts) turnoverMeasureLabelWidth(t, axisStyle),
            ].reduce(math.max) +
            1;
        final distinct = widget.monthLabelsNeedYears ||
            widget.axisGrain == TurnoverAxisGrain.year;

        List<double> valuesFor(List<TurnoverChartSlot> sl) => [
              for (final x in sl)
                centsToMoney(
                  turnoverSlotCents(slot: x, dayCents: widget.dayCents),
                ),
            ];

        var plotW = (chartW - provisionalY - leftInset - rightInset)
            .clamp(1.0, double.infinity);
        final slots = turnoverBuildChartSlots(
          from: widget.rangeStart,
          to: widget.rangeEnd,
          grain: widget.axisGrain,
          fitCount: natural.length,
        );
        final values = valuesFor(slots);
        final yScale = turnoverYAxisScale(
          peak: values.reduce((a, b) => a > b ? a : b),
          plotHeight: plotH,
          maxIntervals: 5,
        );
        final yAxisFinal = turnoverYAxisReservedSize(
          scale: yScale,
          labelStyle: yLabelStyle,
        );
        plotW = (chartW - yAxisFinal - leftInset - rightInset)
            .clamp(1.0, double.infinity);

        final nBars = slots.length;
        final maxBarW = switch (widget.axisGrain) {
          TurnoverAxisGrain.day => 8.0,
          TurnoverAxisGrain.month => 14.0,
          TurnoverAxisGrain.year => 18.0,
        };
        final pitch0 = nBars <= 1 ? plotW : (plotW - edgeW) / (nBars - 1);
        final barW = turnoverPlannedBarWidth(
          pitch: pitch0,
          maxBarWidth: maxBarW,
        );
        final geo = TurnoverBarGeometry(
          plotWidth: plotW,
          barCount: nBars,
          edge: edgeW,
          barWidth: barW,
        );
        _geo = geo;

        final plotLeft = yAxisFinal + leftInset;
        final axisSlots = <TurnoverAxisLabelSlot>[
          for (final j in turnoverUnitLabelBars(
            barCount: nBars,
            pitch: geo.pitch,
            labelWidth: edgeW,
            texts: naturalTexts,
            distinctTexts: distinct,
          ))
            if (j < nBars)
              () {
                // First bar = range start, last bar = range end (exactly the
                // header dates); every bar is one unit, so it is its date.
                final t = turnoverAxisBarLabel(
                  bucket: j == 0
                      ? widget.rangeStart
                      : j == nBars - 1
                          ? widget.rangeEnd
                          : natural[j],
                  grain: widget.axisGrain,
                  isFirstLabel: j == 0,
                  isLastLabel: j == nBars - 1,
                  rangeStart: widget.rangeStart,
                  rangeEnd: widget.rangeEnd,
                  locale: widget.locale,
                  monthLabelsNeedYears: widget.monthLabelsNeedYears,
                );
                final w = turnoverMeasureLabelWidth(t, axisStyle);
                return TurnoverAxisLabelSlot(
                  barIndex: j,
                  text: t,
                  left: plotLeft + geo.centerX(j) - w / 2,
                  width: w,
                );
              }(),
        ];

        // One unit per bar: the tooltip shows that single day / month / year.
        String tooltipDate(int i) {
          final s = slots[i];
          return turnoverBucketTooltip(
            bucketStart: s.start,
            bucketEnd: s.end,
            rangeStart: widget.rangeStart,
            rangeEnd: widget.rangeEnd,
            grain: widget.axisGrain,
            locale: widget.locale,
          );
        }

        // Dismiss tooltip when tapping outside the chart card.
        return TapRegion(
          onTapOutside: (_) => _clearSelection(),
          child: Stack(
          children: [
            BarChart(
              duration: Duration.zero,
              BarChartData(
                maxY: yScale.maxY,
                // Centred group with a fixed pitch: bar j sits at
                // [TurnoverBarGeometry.centerX] (end labels fit centred).
                alignment: BarChartAlignment.center,
                groupsSpace: geo.groupsSpace,
                barTouchData: BarTouchData(
                  enabled: false,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1A2332),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    maxContentWidth: 180,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, gi, rod, ri) {
                      final i = group.x;
                      if (i < 0 || i >= values.length) return null;
                      return BarTooltipItem(
                        '${tooltipDate(i)}\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: widget.money.format(values[i]),
                            style: TextStyle(
                              color: widget.neon,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yScale.interval,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: widget.stroke.withValues(alpha: 0.55),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: rightInset,
                      getTitlesWidget: (value, meta) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: yAxisFinal + leftInset,
                      interval: yScale.interval,
                      getTitlesWidget: (v, meta) {
                        if (v <= 0 ||
                            (v - meta.max).abs() < yScale.interval * 0.01) {
                          return const SizedBox.shrink();
                        }
                        final steps = (v / yScale.interval).round();
                        if ((v - steps * yScale.interval).abs() >
                            yScale.interval * 0.01) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: EdgeInsets.only(right: leftInset),
                          child: Text(
                            turnoverYAxisLabel(v),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.right,
                            style: yLabelStyle,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: bottomReserved,
                      interval: 1,
                      // Labels are drawn by the overlay below (flush edges,
                      // equal spacing) — fl_chart only reserves the space.
                      getTitlesWidget: (v, meta) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < values.length; i++)
                    BarChartGroupData(
                      x: i,
                      showingTooltipIndicators:
                          i == _touchedBarIndex ? const [0] : const <int>[],
                      barRods: [
                        BarChartRodData(
                          toY: values[i] > 0
                              ? values[i]
                              : yScale.maxY * 0.03,
                          color: i == _touchedBarIndex
                              ? const Color(0xFFB8FF66)
                              : (values[i] > 0
                                  ? widget.neon
                                  : widget.neon.withValues(alpha: 0.28)),
                          width: barW,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(3),
                            bottomLeft: Radius.zero,
                            bottomRight: Radius.zero,
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: yScale.maxY,
                            color: const Color(0x00000000),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            for (final l in axisSlots)
              Positioned(
                left: l.left,
                width: l.width,
                bottom: bottomReserved - 4 - 12,
                height: 12,
                child: IgnorePointer(
                  child: Text(
                    l.text,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: axisStyle,
                  ),
                ),
              ),
            Positioned(
              left: yAxisFinal + leftInset,
              right: rightInset,
              top: 0,
              bottom: bottomReserved,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => _selectAtPlotX(e.localPosition.dx),
                onPointerMove: (e) => _selectAtPlotX(e.localPosition.dx),
              ),
            ),
          ],
        ),
        );
      },
    );
  }
}

/// RangeSlider thumb selector that ignores taps on the track — only the
/// circular thumbs start an interaction (client).
Thumb? _turnoverThumbsOnlySelector(
  TextDirection textDirection,
  RangeValues values,
  double tapValue,
  Size thumbSize,
  Size trackSize,
  double dx,
) {
  final radius =
      math.max(thumbSize.width, kMinInteractiveDimension) / 2 + 4;
  final startPx = values.start * trackSize.width;
  final endPx = values.end * trackSize.width;
  final tapPx = tapValue * trackSize.width;
  final inStart = (tapPx - startPx).abs() <= radius;
  final inEnd = (tapPx - endPx).abs() <= radius;
  if (inStart && inEnd) {
    final (towardsStart, towardsEnd) = switch (textDirection) {
      TextDirection.ltr => (dx < 0, dx > 0),
      TextDirection.rtl => (dx > 0, dx < 0),
    };
    if (towardsStart) return Thumb.start;
    if (towardsEnd) return Thumb.end;
    return null;
  }
  if (inStart) return Thumb.start;
  if (inEnd) return Thumb.end;
  return null;
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final active = enabled;
    return Opacity(
      opacity: active ? 1 : 0.38,
      child: Pressable(
        onTap: active ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: selected && active ? p.neon : p.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected && active ? p.neon : p.stroke,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected && active ? Colors.black : p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
