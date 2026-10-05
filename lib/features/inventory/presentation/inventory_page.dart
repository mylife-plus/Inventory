import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/inventory/presentation/item_list_tools.dart';
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
  SortState<ItemSortKey> _sort = kDefaultItemSort;
  /// Collapsed category section keys (expanded by default).
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    final picked = await showSortSheet<ItemSortKey>(
      context: context,
      options: itemSortOptions(t),
      current: _sort,
      defaultState: kDefaultItemSort,
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _showFilterSheet() async {
    final t = ref.read(tProvider);
    final cats = ref.read(categoriesProvider).valueOrNull ?? [];
    final items = ref.read(inventoryItemsProvider).valueOrNull ?? [];
    final picked = await showItemFilterSheet(
      context,
      t: t,
      categories: usedCategories(cats, items),
      current: _categoryFilter,
    );
    if (picked != null && mounted) {
      setState(() => _categoryFilter = picked.categoryId);
    }
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
            sortActive: _sort != kDefaultItemSort,
            filterActive: _categoryFilter != null,
            searchActive: _showSearch || _search.text.trim().isNotEmpty,
          ),
          if (_showSearch)
            AppSearchField(
              controller: _search,
              hintText: t('search'),
              onChanged: (_) => setState(() {}),
              onDismiss: () {
                if (mounted) setState(() => _showSearch = false);
              },
            ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const AppLoader(),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) {
                final t = ref.read(tProvider);
                final q = _search.text.trim().toLowerCase();
                final filtered = sortItems(
                  items.where((item) {
                    final matchQ =
                        q.isEmpty || item.title.toLowerCase().contains(q);
                    final matchC = _categoryFilter == null ||
                        (_categoryFilter == '__uncat__'
                            ? item.categoryId == null
                            : item.categoryId == _categoryFilter);
                    return matchQ && matchC;
                  }).toList(),
                  _sort,
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
