import 'package:flutter/material.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';

/// Sort criteria shared by Inventory and Sell → Add items.
enum ItemSortKey { name, price, stock, recent }

/// Default inventory sort: Name A–Z.
const kDefaultItemSort = SortState<ItemSortKey>(ItemSortKey.name);

List<SortOption<ItemSortKey>> itemSortOptions(S t) => [
      SortOption(
        key: ItemSortKey.name,
        icon: Icons.sort_by_alpha_rounded,
        label: t('sort_name_az'),
        reversedLabel: t('sort_name_za'),
      ),
      SortOption(
        key: ItemSortKey.price,
        icon: Icons.payments_rounded,
        label: t('sort_highest_price'),
        reversedLabel: t('sort_lowest_price'),
      ),
      SortOption(
        key: ItemSortKey.stock,
        icon: Icons.inventory_2_outlined,
        label: t('sort_highest_stock'),
        reversedLabel: t('sort_lowest_stock'),
      ),
      SortOption(
        key: ItemSortKey.recent,
        icon: Icons.schedule_rounded,
        label: t('sort_most_recent'),
        reversedLabel: t('sort_oldest'),
      ),
    ];

/// Sorts items (callers group by category afterwards, so the order applies
/// within each category).
List<InventoryItem> sortItems(
  List<InventoryItem> items,
  SortState<ItemSortKey> sort,
) {
  final list = [...items];
  int byName(InventoryItem a, InventoryItem b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  int cmp(InventoryItem a, InventoryItem b) {
    switch (sort.key) {
      case ItemSortKey.name:
        return byName(a, b);
      case ItemSortKey.price:
        // Default direction: highest first.
        final c = b.price.compareTo(a.price);
        return c != 0 ? c : byName(a, b);
      case ItemSortKey.stock:
        final c = b.amount.compareTo(a.amount);
        return c != 0 ? c : byName(a, b);
      case ItemSortKey.recent:
        return b.updatedAt.compareTo(a.updatedAt);
    }
  }

  list.sort((a, b) => sort.reversed ? cmp(b, a) : cmp(a, b));
  return list;
}

/// Categories that still exist on at least one inventory item, A–Z.
List<({String id, String name})> usedCategories(
  List<Category> categories,
  List<InventoryItem> items,
) {
  final usedIds = items.map((i) => i.categoryId).whereType<String>().toSet();
  final list = [
    for (final c in categories)
      if (usedIds.contains(c.id)) (id: c.id, name: c.name),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Shared category filter (Inventory + Sell → Add items).
/// Returns `null` when dismissed, otherwise the chosen category
/// (`categoryId == null` means all categories).
Future<({String? categoryId})?> showItemFilterSheet(
  BuildContext context, {
  required S t,
  required List<({String id, String name})> categories,
  required String? current,
}) {
  var cat = categories.any((c) => c.id == current) ? current : null;
  return showAppSheet<({String? categoryId})>(
    context: context,
    alignTop: true,
    heightFactor: 0.6,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => AppFilterSheet(
        onReset: () => Navigator.pop(ctx, (categoryId: null)),
        onApply: () => Navigator.pop(ctx, (categoryId: cat)),
        child: AppFilterSection(
          title: t('category'),
          child: AppCategoryDropdown(
            categories: categories,
            value: cat,
            onChanged: (v) => setModal(() => cat = v),
          ),
        ),
      ),
    ),
  );
}
