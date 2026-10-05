import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/export/csv_export.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

enum TurnoverPeriod { w2, m1, m3, m6, y1, y2, all }

enum TurnoverSort { highestAmount, mostRecent }

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
  TurnoverPeriod _period = TurnoverPeriod.m1;
  TurnoverSort _sort = TurnoverSort.highestAmount;
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
    final sortedSales = [...sales]..sort((a, b) {
        if (_sort == TurnoverSort.mostRecent) {
          return b.createdAt.compareTo(a.createdAt);
        }
        return a.createdAt.compareTo(b.createdAt);
      });

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
    if (_sort == TurnoverSort.mostRecent) {
      items.sort((a, b) => b.lastSaleAt.compareTo(a.lastSaleAt));
    } else {
      items.sort((a, b) => b.revenue.compareTo(a.revenue));
    }
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

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}. ${DateFormat.MMM().format(d)}. ${d.year}';

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    final picked = await showAppSheet<TurnoverSort>(
      context: context,
      heightFactor: 0.42,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetHeader(title: t('sort')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    AppRadioRow<TurnoverSort>(
                      label: t('sort_highest_amount'),
                      icon: Icons.payments_rounded,
                      value: TurnoverSort.highestAmount,
                      groupValue: _sort,
                      onChanged: (v) => Navigator.pop(ctx, v),
                    ),
                    const SizedBox(height: 8),
                    AppRadioRow<TurnoverSort>(
                      label: t('sort_most_recent'),
                      icon: Icons.schedule_rounded,
                      value: TurnoverSort.mostRecent,
                      groupValue: _sort,
                      onChanged: (v) => Navigator.pop(ctx, v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != _sort) {
      AppHaptics.selection();
      setState(() => _sort = picked);
    }
  }

  Future<void> _showFilterSheet() async {
    final categories =
        ref.read(categoriesProvider).valueOrNull ?? <Category>[];
    var from = _customFrom;
    var to = _customTo;
    var category = _categoryFilter;

    await showAppSheet<void>(
      context: context,
      heightFactor: 0.55,
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickFrom() async {
              final initial = from ?? DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setModalState(() => from = d);
            }

            Future<void> pickTo() async {
              final initial = to ?? DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setModalState(() => to = d);
            }

            String fmt(DateTime? d, String placeholder) {
              if (d == null) return placeholder;
              return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
            }

            Widget dateField({
              required String placeholder,
              required DateTime? value,
              required VoidCallback onTap,
            }) {
              return Pressable(
                onTap: onTap,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: p.cardElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.stroke),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fmt(value, placeholder),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: value == null
                                ? p.textMuted
                                : p.textPrimary,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down_rounded,
                          size: 22, color: p.textMuted),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                AppSheetHeader(title: ref.read(tProvider)('filter')),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: dateField(
                              placeholder: ref.read(tProvider)('from_date'),
                              value: from,
                              onTap: pickFrom,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: dateField(
                              placeholder: ref.read(tProvider)('to_date'),
                              value: to,
                              onTap: pickTo,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: p.cardElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.stroke),
                        ),
                        alignment: Alignment.center,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            isExpanded: true,
                            value: category,
                            hint: Text(
                              ref.read(tProvider)('category'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: p.textMuted,
                              ),
                            ),
                            icon: const Icon(Icons.arrow_drop_down_rounded),
                            dropdownColor: p.cardElevated,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  ref.read(tProvider)('all_categories'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                              ...categories.map(
                                (c) => DropdownMenuItem<String?>(
                                  value: c.id,
                                  child: Text(
                                    c.name,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setModalState(() => category = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AppSheetActions(
                  onReset: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _customFrom = null;
                      _customTo = null;
                      _categoryFilter = null;
                      _slider = const RangeValues(0, 1);
                    });
                  },
                  onApply: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _customFrom = from;
                      _customTo = to;
                      _categoryFilter = category;
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );
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
                    final inventoryById = {
                      for (final i in inventory) i.id: i,
                    };

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
                          (i) =>
                              q.isEmpty || i.title.toLowerCase().contains(q),
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
                      final dk =
                          '$mk-${d.day.toString().padLeft(2, '0')}';
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
                      final amountOnly =
                          money.formatAmount(item.unitPrice).trim();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MediaListCard(
                          onTap: () =>
                              context.push('/inventory/item/${item.itemId}'),
                          thumb: CardThumb(
                            path: inv?.photoPath,
                            badge: badge,
                          ),
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
                        out.add(
                          SectionHeader(
                            title: '$year',
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
                        final sortedMonths = months.keys.toList()
                          ..sort((a, b) => b.compareTo(a));
                        for (final month in sortedMonths) {
                          final list = months[month]!;
                          final monthTotal =
                              list.fold<double>(0, (s, i) => s + i.revenue);
                          final monthName = DateFormat.MMMM().format(
                            DateTime(year, month),
                          );
                          out.add(
                            SectionHeader(
                              title: monthName,
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
                          out.addAll(list.map(buildItemCard));
                        }
                      }
                      return out;
                    }

                    final chartFrom = range.$1 ??
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
                                      .soldItems(
                                        from: range.$1,
                                        to: range.$2,
                                      );
                                  await CsvExportService().exportTurnover(
                                    items: exportItems,
                                    sales: exportSales,
                                    currency:
                                        settings?.currencySymbol ?? '€',
                                    companyName: settings?.companyName,
                                    from: range.$1,
                                    to: range.$2,
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
                                              color: p.stroke
                                                  .withValues(alpha: 0.55),
                                              strokeWidth: 1,
                                            ),
                                          ),
                                          borderData:
                                              FlBorderData(show: false),
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
                                                  if (v == 0 ||
                                                      v == meta.max) {
                                                    return const SizedBox
                                                        .shrink();
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
                                                  final n =
                                                      chartValues.length;
                                                  if (n <= 6) return 1.0;
                                                  return (n / 5)
                                                      .ceilToDouble();
                                                }(),
                                                getTitlesWidget: (v, meta) {
                                                  final i = v.round();
                                                  if (i < 0 ||
                                                      i >= days.length) {
                                                    return const SizedBox
                                                        .shrink();
                                                  }
                                                  final y =
                                                      days[i].split('-').first;
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
                                            for (var i = 0;
                                                i < chartValues.length;
                                                i++)
                                              BarChartGroupData(
                                                x: i,
                                                barRods: [
                                                  BarChartRodData(
                                                    toY: chartValues[i],
                                                    color: p.neon,
                                                    width: chartValues.length >
                                                            40
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
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final e in [
                                (TurnoverPeriod.w2, '2w'),
                                (TurnoverPeriod.m1, '1m'),
                                (TurnoverPeriod.m3, '3m'),
                                (TurnoverPeriod.m6, '6m'),
                                (TurnoverPeriod.y1, '1y'),
                                (TurnoverPeriod.y2, '2y'),
                                (TurnoverPeriod.all, 'All'),
                              ])
                                _PeriodChip(
                                  label: e.$2,
                                  selected: !_usingCustomRange &&
                                      _period == e.$1,
                                  onTap: () => _selectPeriod(e.$1),
                                ),
                            ],
                          ),
                        ),
                        if (!_usingCustomRange) ...[
                          const SizedBox(height: 2),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 5,
                              activeTrackColor: p.neon,
                              inactiveTrackColor:
                                  p.neon.withValues(alpha: 0.28),
                              overlayColor: const Color(0xFFFFD54F)
                                  .withValues(alpha: 0.18),
                              rangeThumbShape:
                                  const RoundRangeSliderThumbShape(
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
                        Row(
                          children: [
                            HeaderActionIcon(
                              asset: AppAssets.sort,
                              onTap: _showSortSheet,
                            ),
                            const SizedBox(width: 48),
                            HeaderActionIcon(
                              asset: AppAssets.filter,
                              onTap: _showFilterSheet,
                            ),
                            const SizedBox(width: 48),
                            HeaderActionIcon(
                              asset: AppAssets.search,
                              onTap: () =>
                                  setState(() => _showSearch = !_showSearch),
                            ),
                          ],
                        ),
                        if (_showSearch)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextField(
                              controller: _search,
                              autofocus: true,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: t('search_sold_items'),
                                prefixIcon:
                                    const Icon(Icons.search, size: 20),
                                isDense: true,
                              ),
                            ),
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? p.neon : p.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? p.neon : p.stroke,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
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
