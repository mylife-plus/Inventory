import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _search = TextEditingController();
  String? _categoryFilter;
  bool _showSearch = false;
  _InvSort _sort = _InvSort.name;
  /// Collapsed category section keys (expanded by default).
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    await showAppSheet<void>(
      context: context,
      heightFactor: 0.48,
      alignTop: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Widget row({
              required String label,
              required IconData icon,
              required bool selected,
              required IconData? directionIcon,
              required VoidCallback onTap,
            }) {
              final p = AppPalette.of(ctx);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    AppHaptics.selection();
                    onTap();
                    setModal(() {});
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? p.fabBorder : p.stroke,
                        width: selected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? p.fabBorder.withValues(alpha: 0.18)
                                : p.cardElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            icon,
                            size: 20,
                            color: selected ? p.fabBorder : p.textMuted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (selected && directionIcon != null) ...[
                          Icon(
                            directionIcon,
                            size: 22,
                            color: p.fabBorder,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 22,
                          color: selected ? p.fabBorder : p.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final nameSelected =
                _sort == _InvSort.name || _sort == _InvSort.nameDesc;
            final priceSelected =
                _sort == _InvSort.priceHigh || _sort == _InvSort.priceLow;
            final stockSelected =
                _sort == _InvSort.stockHigh || _sort == _InvSort.stockLow;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSheetHeader(title: t('sort')),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        row(
                          label: nameSelected && _sort == _InvSort.nameDesc
                              ? t('sort_name_za')
                              : t('sort_name_az'),
                          icon: Icons.sort_by_alpha_rounded,
                          selected: nameSelected,
                          directionIcon: nameSelected
                              ? (_sort == _InvSort.name
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded)
                              : null,
                          onTap: () {
                            setState(() {
                              if (_sort == _InvSort.name) {
                                _sort = _InvSort.nameDesc;
                              } else if (_sort == _InvSort.nameDesc) {
                                _sort = _InvSort.name;
                              } else {
                                _sort = _InvSort.name;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        row(
                          label: priceSelected && _sort == _InvSort.priceLow
                              ? t('sort_lowest_price')
                              : t('sort_highest_price'),
                          icon: Icons.payments_rounded,
                          selected: priceSelected,
                          directionIcon: priceSelected
                              ? (_sort == _InvSort.priceHigh
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded)
                              : null,
                          onTap: () {
                            setState(() {
                              if (_sort == _InvSort.priceHigh) {
                                _sort = _InvSort.priceLow;
                              } else if (_sort == _InvSort.priceLow) {
                                _sort = _InvSort.priceHigh;
                              } else {
                                _sort = _InvSort.priceHigh;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        row(
                          label: stockSelected && _sort == _InvSort.stockLow
                              ? t('sort_lowest_stock')
                              : t('sort_highest_stock'),
                          icon: Icons.inventory_2_outlined,
                          selected: stockSelected,
                          directionIcon: stockSelected
                              ? (_sort == _InvSort.stockHigh
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded)
                              : null,
                          onTap: () {
                            setState(() {
                              if (_sort == _InvSort.stockHigh) {
                                _sort = _InvSort.stockLow;
                              } else if (_sort == _InvSort.stockLow) {
                                _sort = _InvSort.stockHigh;
                              } else {
                                _sort = _InvSort.stockHigh;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        row(
                          label: t('sort_most_recent'),
                          icon: Icons.schedule_rounded,
                          selected: _sort == _InvSort.recent,
                          directionIcon: null,
                          onTap: () {
                            setState(() => _sort = _InvSort.recent);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showFilterSheet() async {
    final t = ref.read(tProvider);
    final cats = ref.read(categoriesProvider).valueOrNull ?? [];
    final items = ref.read(inventoryItemsProvider).valueOrNull ?? [];
    final usedIds = items
        .map((i) => i.categoryId)
        .whereType<String>()
        .toSet();
    final usedCats = cats
        .where((c) => usedIds.contains(c.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    var cat = _categoryFilter;
    if (cat != null && cat != '__uncat__' && !usedIds.contains(cat)) {
      cat = null;
    }

    final applied = await showAppSheet<bool>(
      context: context,
      heightFactor: 0.42,
      alignTop: true,
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSheetHeader(title: t('filter')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: p.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.stroke),
                    ),
                    alignment: Alignment.center,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: cat,
                        hint: Text(
                          t('all_categories'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: p.textMuted,
                          ),
                        ),
                        icon: Icon(
                          Icons.arrow_drop_down_rounded,
                          color: p.textMuted,
                        ),
                        dropdownColor: p.cardElevated,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(t('all_categories')),
                          ),
                          ...usedCats.map(
                            (c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          ),
                        ],
                        onChanged: (v) => setModal(() => cat = v),
                      ),
                    ),
                  ),
                ),
                AppSheetActions(
                  onReset: () {
                    Navigator.pop(ctx);
                    setState(() => _categoryFilter = null);
                  },
                  onApply: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() => _categoryFilter = cat);
    }
  }

  List<InventoryItem> _sorted(List<InventoryItem> items) {
    final list = [...items];
    switch (_sort) {
      case _InvSort.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _InvSort.name:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _InvSort.nameDesc:
        list.sort(
            (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      case _InvSort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _InvSort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _InvSort.stockHigh:
        list.sort((a, b) => b.amount.compareTo(a.amount));
      case _InvSort.stockLow:
        list.sort((a, b) => a.amount.compareTo(b.amount));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final itemsAsync = ref.watch(inventoryItemsProvider);
    final catsAsync = ref.watch(categoriesProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final t = ref.watch(tProvider);
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );

    // Clear stale category filter if the category was deleted / unused.
    final cats = catsAsync.valueOrNull;
    final items = itemsAsync.valueOrNull;
    if (_categoryFilter != null &&
        _categoryFilter != '__uncat__' &&
        cats != null &&
        items != null) {
      final usedIds = items
          .map((i) => i.categoryId)
          .whereType<String>()
          .toSet();
      final stillValid = cats.any((c) => c.id == _categoryFilter) &&
          usedIds.contains(_categoryFilter);
      if (!stillValid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _categoryFilter != null) {
            setState(() => _categoryFilter = null);
          }
        });
      }
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SquareFab(
        onPressed: () => context.push('/inventory/item'),
      ),
      body: Column(
        children: [
          ClientHeader(
            section: 0,
            title: t('inventory'),
            titleAsset: AppAssets.inventory,
            showSell: true,
            onSearch: () => setState(() => _showSearch = !_showSearch),
            onFilter: _showFilterSheet,
            onMenu: _showSortSheet,
            sortActive: _sort != _InvSort.name,
            filterActive: _categoryFilter != null,
            searchActive: _showSearch,
          ),
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: t('search'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const AppLoader(),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) {
                final t = ref.read(tProvider);
                final q = _search.text.trim().toLowerCase();
                final filtered = _sorted(
                  items.where((item) {
                    final matchQ =
                        q.isEmpty || item.title.toLowerCase().contains(q);
                    final matchC = _categoryFilter == null ||
                        (_categoryFilter == '__uncat__'
                            ? item.categoryId == null
                            : item.categoryId == _categoryFilter);
                    return matchQ && matchC;
                  }).toList(),
                );

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: t('no_items'),
                    subtitle: t('add_first_item'),
                  );
                }

                final grouped = <String, List<InventoryItem>>{};
                for (final item in filtered) {
                  final key = item.categoryName ?? t('uncategorized');
                  grouped.putIfAbsent(key, () => []).add(item);
                }

                final sortedEntries = grouped.entries.toList()
                  ..sort((a, b) =>
                      a.key.toLowerCase().compareTo(b.key.toLowerCase()));

                final categoryTotal = <String, double>{};
                for (final entry in sortedEntries) {
                  categoryTotal[entry.key] = entry.value.fold<double>(
                    0,
                    (s, i) => s + (i.price * i.amount),
                  );
                }
                final grandTotal =
                    categoryTotal.values.fold<double>(0, (s, v) => s + v);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    TotalLine(
                        label: t('total'), value: money.format(grandTotal)),
                    ...sortedEntries.expand((entry) {
                      final open = !_collapsed.contains(entry.key);
                      return [
                        SectionHeader(
                          title: entry.key,
                          expanded: open,
                          onToggle: () => setState(() {
                            if (open) {
                              _collapsed.add(entry.key);
                            } else {
                              _collapsed.remove(entry.key);
                            }
                          }),
                          trailing: Text(
                            money.format(categoryTotal[entry.key] ?? 0),
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                              height: 1.15,
                              color: p.textPrimary.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                        if (open)
                          ...entry.value.asMap().entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: FadeSlide(
                                delay: Duration(milliseconds: 30 * e.key),
                                child: _InventoryCard(
                                  item: e.value,
                                  money: money,
                                  onTap: () => context
                                      .push('/inventory/item/${e.value.id}'),
                                ),
                              ),
                            ),
                          ),
                      ];
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _InvSort {
  name,
  nameDesc,
  priceHigh,
  priceLow,
  stockHigh,
  stockLow,
  recent,
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.money,
    required this.onTap,
  });

  final InventoryItem item;
  final MoneyFormatter money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final amountOnly = money.formatAmount(item.price);
    final total = money.format(item.price * item.amount);

    return MediaListCard(
      onTap: onTap,
      borderColor: item.isLowStock ? p.danger : null,
      thumb: CardThumb(path: item.photoPath, badge: item.stockBadge),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
                  amount: amountOnly.trim(),
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
                child: CardTotalLine(value: total),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
