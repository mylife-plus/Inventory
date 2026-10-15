import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/export/csv_export.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/inventory/presentation/item_list_tools.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

enum TurnoverPeriod { w2, m1, m3, m6, y1, y2, all }

enum TurnoverSortKey { amount, recent }

const _kDefaultTurnoverSort = SortState<TurnoverSortKey>(
  TurnoverSortKey.amount,
);

class _TurnoverItemAgg {
  const _TurnoverItemAgg({
    required this.itemId,
    required this.title,
    required this.quantity,
    required this.revenue,
    required this.unitPrice,
    required this.lastSaleAt,
    this.unit,
  });

  final String itemId;
  final String title;
  final String? unit;
  final double unitPrice;
  final double quantity;
  final double revenue;
  final DateTime lastSaleAt;
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

  /// Slider window within the selected period (0–1 of period span).
  RangeValues _slider = const RangeValues(0, 1);
  bool get _usingCustomRange => _customFrom != null || _customTo != null;
  bool _showSearch = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  (DateTime, DateTime) _periodBounds() {
    final now = DateTime.now();
    final end = _endOfDay(now);
    switch (_period) {
      case TurnoverPeriod.w2:
        return (_startOfDay(now.subtract(const Duration(days: 13))), end);
      case TurnoverPeriod.m1:
        return (_startOfDay(now.subtract(const Duration(days: 30))), end);
      case TurnoverPeriod.m3:
        return (_startOfDay(now.subtract(const Duration(days: 90))), end);
      case TurnoverPeriod.m6:
        return (_startOfDay(now.subtract(const Duration(days: 180))), end);
      case TurnoverPeriod.y1:
        return (_startOfDay(now.subtract(const Duration(days: 365))), end);
      case TurnoverPeriod.y2:
        return (_startOfDay(now.subtract(const Duration(days: 730))), end);
      case TurnoverPeriod.all:
        return (_startOfDay(now.subtract(const Duration(days: 3650))), end);
    }
  }

  (DateTime?, DateTime?) _effectiveRange() {
    if (_usingCustomRange) {
      return (
        _customFrom != null ? _startOfDay(_customFrom!) : null,
        _customTo != null ? _endOfDay(_customTo!) : null,
      );
    }
    if (_period == TurnoverPeriod.all &&
        _slider.start <= 0.001 &&
        _slider.end >= 0.999) {
      return (null, null);
    }
    final bounds = _periodBounds();
    final spanMs = bounds.$2
        .difference(bounds.$1)
        .inMilliseconds
        .toDouble()
        .clamp(1, double.infinity);
    final from = bounds.$1.add(
      Duration(milliseconds: (spanMs * _slider.start).round()),
    );
    final to = bounds.$1.add(
      Duration(milliseconds: (spanMs * _slider.end).round()),
    );
    return (_startOfDay(from), _endOfDay(to));
  }

  bool _saleInRange(Sale sale, DateTime? from, DateTime? to) {
    final at = sale.createdAt;
    if (from != null && at.isBefore(from)) return false;
    if (to != null && at.isAfter(to)) return false;
    return true;
  }

  List<_TurnoverItemAgg> _aggregateItems(
    List<Sale> sales,
    Map<String, InventoryItem> inventoryById,
  ) {
    // Oldest → newest so the latest title / price wins.
    final sortedSales = [...sales]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final itemMap = <String, _TurnoverItemAgg>{};
    for (final sale in sortedSales) {
      for (final line in sale.lines) {
        if (_categoryFilter != null) {
          final inv = inventoryById[line.itemId];
          if (inv?.categoryId != _categoryFilter) continue;
        }
        final prev = itemMap[line.itemId];
        final lastSaleAt = prev == null
            ? sale.createdAt
            : (sale.createdAt.isAfter(prev.lastSaleAt)
                  ? sale.createdAt
                  : prev.lastSaleAt);
        itemMap[line.itemId] = _TurnoverItemAgg(
          itemId: line.itemId,
          title: line.title,
          unit: line.unit,
          unitPrice: line.unitPrice,
          quantity: (prev?.quantity ?? 0) + line.quantity,
          revenue: (prev?.revenue ?? 0) + line.lineTotal,
          lastSaleAt: lastSaleAt,
        );
      }
    }

    final items = itemMap.values.toList();
    int cmp(_TurnoverItemAgg a, _TurnoverItemAgg b) =>
        _sort.key == TurnoverSortKey.recent
        ? b.lastSaleAt.compareTo(a.lastSaleAt)
        : b.revenue.compareTo(a.revenue);
    items.sort((a, b) => _sort.reversed ? cmp(b, a) : cmp(a, b));
    return items;
  }

  void _selectPeriod(TurnoverPeriod period) {
    setState(() {
      _period = period;
      _customFrom = null;
      _customTo = null;
      _slider = const RangeValues(0, 1);
    });
  }

  /// X-axis label for a `yyyy-MM-dd` day bucket, picked by how long the
  /// shown range is: day + month for up to ~3 months ("8.10." / "10/8"),
  /// month for up to a year ("Okt"), otherwise month + year ("Okt 26").
  String _barLabel(String day, int spanDays, String locale) {
    final d = DateTime.tryParse(day);
    if (d == null) return day;
    if (spanDays <= 95) return DateFormat.Md(locale).format(d);
    if (spanDays <= 366) {
      return DateFormat.MMM(locale).format(d).replaceAll('.', '');
    }
    return DateFormat('MMM yy', locale).format(d).replaceAll('.', '');
  }

  String _fmtShort(DateTime d) => formatDateShort(d, ref.read(tProvider).code);

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    final picked = await showSortSheet<TurnoverSortKey>(
      context: context,
      options: [
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
            final d = await pickFilterDate(context, isFrom ? from : to);
            if (d == null) return;
            setModal(() => isFrom ? from = d : to = d);
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
      setState(() {
        final cleared = from == null && to == null;
        _customFrom = from;
        _customTo = to;
        _categoryFilter = category;
        if (cleared) _slider = const RangeValues(0, 1);
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
    final range = _effectiveRange();

    return Scaffold(
      body: Column(
        children: [
          ClientHeader(
            section: 2,
            title: t('turnover'),
            titleAsset: AppAssets.turnover,
            showListActions: false,
          ),
          Expanded(
            child: salesAsync.when(
              loading: () => const AppLoader(),
              error: (e, _) => Center(child: Text('$e')),
              data: (allSales) {
                return inventoryAsync.when(
                  loading: () => const AppLoader(),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (inventory) {
                    final inventoryById = {for (final i in inventory) i.id: i};

                    final sales = allSales
                        .where((s) => _saleInRange(s, range.$1, range.$2))
                        .toList();

                    final byDay = <String, double>{};
                    for (final s in sales) {
                      final key =
                          '${s.createdAt.year}-${s.createdAt.month.toString().padLeft(2, '0')}-${s.createdAt.day.toString().padLeft(2, '0')}';
                      byDay[key] = (byDay[key] ?? 0) + s.total;
                    }
                    final days = byDay.keys.toList()..sort();
                    final chartValues = days.map((d) => byDay[d]!).toList();

                    final q = _search.text.trim().toLowerCase();
                    final items = _aggregateItems(sales, inventoryById)
                        .where(
                          (i) => q.isEmpty || i.title.toLowerCase().contains(q),
                        )
                        .toList();

                    // Real averages from actual sale buckets (no fake *30/*365).
                    final yearBuckets = <int, double>{};
                    final monthBuckets = <String, double>{};
                    final dayBuckets = <String, double>{};
                    for (final s in sales) {
                      final d = s.createdAt;
                      yearBuckets[d.year] =
                          (yearBuckets[d.year] ?? 0) + s.total;
                      final mk =
                          '${d.year}-${d.month.toString().padLeft(2, '0')}';
                      monthBuckets[mk] = (monthBuckets[mk] ?? 0) + s.total;
                      final dk = '$mk-${d.day.toString().padLeft(2, '0')}';
                      dayBuckets[dk] = (dayBuckets[dk] ?? 0) + s.total;
                    }
                    double avgOf(Iterable<double> values) {
                      if (values.isEmpty) return 0;
                      return values.reduce((a, b) => a + b) / values.length;
                    }

                    final yearAvg = avgOf(yearBuckets.values);
                    final monthAvg = avgOf(monthBuckets.values);
                    final dayAvg = avgOf(dayBuckets.values);

                    Widget buildItemCard(_TurnoverItemAgg item) {
                      final inv = inventoryById[item.itemId];
                      final badge = formatQty(item.quantity);
                      final amountOnly = money
                          .formatAmount(item.unitPrice)
                          .trim();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MediaListCard(
                          onTap: () =>
                              context.push('/inventory/item/${item.itemId}'),
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
                      if (items.isEmpty) {
                        return [
                          Text('—', style: TextStyle(color: p.textSecondary)),
                        ];
                      }
                      final byYear = <int, Map<int, List<_TurnoverItemAgg>>>{};
                      for (final item in items) {
                        final y = item.lastSaleAt.year;
                        final m = item.lastSaleAt.month;
                        byYear
                            .putIfAbsent(y, () => {})
                            .putIfAbsent(m, () => [])
                            .add(item);
                      }
                      final sortedYears = byYear.keys.toList()
                        ..sort((a, b) => b.compareTo(a));
                      final out = <Widget>[];
                      for (final year in sortedYears) {
                        final months = byYear[year]!;
                        final yearTotal = months.values
                            .expand((e) => e)
                            .fold<double>(0, (s, i) => s + i.revenue);
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
                          final list = months[month]!;
                          final monthTotal = list.fold<double>(
                            0,
                            (s, i) => s + i.revenue,
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

                    final chartFrom =
                        range.$1 ??
                        (sales.isEmpty
                            ? DateTime.now()
                            : sales
                                  .map((s) => s.createdAt)
                                  .reduce((a, b) => a.isBefore(b) ? a : b));
                    final chartTo = range.$2 ?? DateTime.now();
                    final chartRangeLabel =
                        '${_fmtShort(chartFrom)} - ${_fmtShort(chartTo)}';

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      children: [
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
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                tooltip: t('export_csv'),
                                onPressed: () async {
                                  final exportSales = await ref
                                      .read(saleRepositoryProvider)
                                      .listInRange(
                                        from: range.$1,
                                        to: range.$2,
                                      );
                                  final exportItems = await ref
                                      .read(saleRepositoryProvider)
                                      .soldItems(from: range.$1, to: range.$2);
                                  if (!context.mounted) return;
                                  await CsvExportService().exportTurnover(
                                    context: context,
                                    items: exportItems,
                                    sales: exportSales,
                                    currency: settings?.currencySymbol ?? '€',
                                    companyName: settings?.companyName,
                                    from: range.$1,
                                    to: range.$2,
                                    t: t.call,
                                  );
                                },
                                icon: Icon(
                                  Icons.ios_share_rounded,
                                  size: 26,
                                  color: p.textMuted,
                                ),
                              ),
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
                                child: chartValues.isEmpty
                                    ? Center(
                                        child: Text(
                                          t('no_sales_period'),
                                          style: TextStyle(
                                            color: p.textSecondary,
                                          ),
                                        ),
                                      )
                                    : BarChart(
                                        BarChartData(
                                          maxY: () {
                                            final m = chartValues.reduce(
                                              (a, b) => a > b ? a : b,
                                            );
                                            return (m <= 0 ? 1.0 : m * 1.15)
                                                .toDouble();
                                          }(),
                                          gridData: FlGridData(
                                            show: true,
                                            drawVerticalLine: false,
                                            getDrawingHorizontalLine: (v) =>
                                                FlLine(
                                                  color: p.stroke.withValues(
                                                    alpha: 0.55,
                                                  ),
                                                  strokeWidth: 1,
                                                ),
                                          ),
                                          borderData: FlBorderData(show: false),
                                          titlesData: FlTitlesData(
                                            topTitles: const AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: false,
                                              ),
                                            ),
                                            rightTitles: const AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: false,
                                              ),
                                            ),
                                            leftTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                reservedSize: 34,
                                                getTitlesWidget: (v, meta) {
                                                  if (v == 0 || v == meta.max) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  final label = v >= 1000
                                                      ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k'
                                                      : v.toInt().toString();
                                                  return Text(
                                                    label,
                                                    style: TextStyle(
                                                      color: p.textMuted,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            bottomTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                reservedSize: 22,
                                                interval: () {
                                                  final n = chartValues.length;
                                                  if (n <= 6) return 1.0;
                                                  return (n / 5).ceilToDouble();
                                                }(),
                                                getTitlesWidget: (v, meta) {
                                                  final i = v.round();
                                                  if (i < 0 ||
                                                      i >= days.length) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  final y = _barLabel(
                                                    days[i],
                                                    chartTo
                                                        .difference(chartFrom)
                                                        .inDays,
                                                    t.code,
                                                  );
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      y,
                                                      style: TextStyle(
                                                        color: p.textMuted,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          barGroups: [
                                            for (
                                              var i = 0;
                                              i < chartValues.length;
                                              i++
                                            )
                                              BarChartGroupData(
                                                x: i,
                                                barRods: [
                                                  BarChartRodData(
                                                    toY: chartValues[i],
                                                    color: p.neon,
                                                    width:
                                                        chartValues.length > 40
                                                        ? 4
                                                        : 8,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          3,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
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
                                    selected:
                                        !_usingCustomRange && _period == e.$1,
                                    onTap: () => _selectPeriod(e.$1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (!_usingCustomRange) ...[
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
                            ),
                            child: RangeSlider(
                              values: _slider,
                              min: 0,
                              max: 1,
                              divisions: 40,
                              onChanged: (v) {
                                AppHaptics.selection();
                                setState(() {
                                  _slider = RangeValues(
                                    (v.start).clamp(0.0, v.end),
                                    (v.end).clamp(v.start, 1.0),
                                  );
                                });
                              },
                            ),
                          ),
                        ],
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
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AverageStrip extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                onTap: () => pickAndSaveCurrency(context, ref),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.black.withValues(alpha: 0.25),
              ),
              _AvgCell(
                label: monthLabel,
                value: monthValue,
                onTap: () => pickAndSaveCurrency(context, ref),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.black.withValues(alpha: 0.25),
              ),
              _AvgCell(
                label: dayLabel,
                value: dayValue,
                onTap: () => pickAndSaveCurrency(context, ref),
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
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        onTap: onTap,
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
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.neon : p.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? p.neon : p.stroke),
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
              color: selected ? Colors.black : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
