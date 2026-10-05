import 'package:flutter/material.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';

/// Sort criteria shared by Customers and Sell → Select customer.
enum CustomerSortKey { name, spent, purchases, recent }

const kDefaultCustomerSort = SortState<CustomerSortKey>(CustomerSortKey.name);

List<SortOption<CustomerSortKey>> customerSortOptions(S t) => [
      SortOption(
        key: CustomerSortKey.name,
        icon: Icons.sort_by_alpha_rounded,
        label: t('sort_name_az'),
        reversedLabel: t('sort_name_za'),
      ),
      SortOption(
        key: CustomerSortKey.spent,
        icon: Icons.payments_rounded,
        label: t('sort_highest_spend'),
        reversedLabel: t('sort_lowest_spend'),
      ),
      SortOption(
        key: CustomerSortKey.purchases,
        icon: Icons.shopping_bag_outlined,
        label: t('sort_most_purchases'),
        reversedLabel: t('sort_fewest_purchases'),
      ),
      SortOption(
        key: CustomerSortKey.recent,
        icon: Icons.schedule_rounded,
        label: t('sort_most_recent'),
        reversedLabel: t('sort_oldest'),
      ),
    ];

List<Customer> sortCustomers(
  List<Customer> list,
  SortState<CustomerSortKey> sort,
  Map<String, CustomerStats> stats,
) {
  int byName(Customer a, Customer b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  // Most recent = last purchase, falling back to when the customer was added.
  DateTime recentOf(Customer c) => stats[c.id]?.lastPurchaseAt ?? c.createdAt;
  int cmp(Customer a, Customer b) {
    switch (sort.key) {
      case CustomerSortKey.name:
        return byName(a, b);
      case CustomerSortKey.spent:
        final c = (stats[b.id]?.totalSpent ?? 0)
            .compareTo(stats[a.id]?.totalSpent ?? 0);
        return c != 0 ? c : byName(a, b);
      case CustomerSortKey.purchases:
        final c = (stats[b.id]?.purchaseCount ?? 0)
            .compareTo(stats[a.id]?.purchaseCount ?? 0);
        return c != 0 ? c : byName(a, b);
      case CustomerSortKey.recent:
        return recentOf(b).compareTo(recentOf(a));
    }
  }

  return [...list]..sort((a, b) => sort.reversed ? cmp(b, a) : cmp(a, b));
}

enum ContactKind { phone, email, whatsapp, facebook, instagram, linkedin, telegram }

enum PurchaseFilter { all, withPurchases, noPurchases }

class CustomerFilter {
  const CustomerFilter({
    this.contacts = const {},
    this.purchases = PurchaseFilter.all,
  });

  /// Customer must have every selected contact option.
  final Set<ContactKind> contacts;
  final PurchaseFilter purchases;

  bool get isActive => contacts.isNotEmpty || purchases != PurchaseFilter.all;

  bool matches(Customer c, CustomerStats? stats) {
    bool has(String? v) => v != null && v.trim().isNotEmpty;
    for (final k in contacts) {
      final ok = switch (k) {
        ContactKind.phone => has(c.phone),
        ContactKind.email => has(c.email),
        ContactKind.whatsapp => has(c.whatsapp),
        ContactKind.facebook => has(c.facebook),
        ContactKind.instagram => has(c.instagram),
        ContactKind.linkedin => has(c.linkedin),
        ContactKind.telegram => has(c.telegram),
      };
      if (!ok) return false;
    }
    final count = stats?.purchaseCount ?? 0;
    return switch (purchases) {
      PurchaseFilter.all => true,
      PurchaseFilter.withPurchases => count > 0,
      PurchaseFilter.noPurchases => count == 0,
    };
  }
}

bool customerMatchesQuery(Customer c, String q) {
  if (q.isEmpty) return true;
  bool hit(String? v) => v?.toLowerCase().contains(q) ?? false;
  return hit(c.name) ||
      hit(c.lastName) ||
      hit(c.shortName) ||
      hit(c.displayName) ||
      hit(c.phone) ||
      hit(c.email) ||
      hit(c.whatsapp) ||
      hit(c.facebook) ||
      hit(c.instagram) ||
      hit(c.linkedin) ||
      hit(c.telegram);
}

/// Shared customer filter sheet. Returns null when dismissed.
Future<CustomerFilter?> showCustomerFilterSheet(
  BuildContext context, {
  required S t,
  required CustomerFilter current,
}) {
  final contacts = {...current.contacts};
  var purchases = current.purchases;
  String contactLabel(ContactKind k) => t(k.name);
  return showAppSheet<CustomerFilter>(
    context: context,
    alignTop: true,
    heightFactor: 0.7,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => AppFilterSheet(
        onReset: () => Navigator.pop(ctx, const CustomerFilter()),
        onApply: () => Navigator.pop(
          ctx,
          CustomerFilter(contacts: contacts, purchases: purchases),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFilterSection(
              title: t('contact_options'),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in ContactKind.values)
                    AppChoiceChip(
                      label: contactLabel(k),
                      selected: contacts.contains(k),
                      onTap: () => setModal(() {
                        if (!contacts.remove(k)) contacts.add(k);
                      }),
                    ),
                ],
              ),
            ),
            AppFilterSection(
              title: t('purchases'),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, key) in const [
                    (PurchaseFilter.all, 'all'),
                    (PurchaseFilter.withPurchases, 'with_purchases'),
                    (PurchaseFilter.noPurchases, 'no_purchases'),
                  ])
                    AppChoiceChip(
                      label: t(key),
                      selected: purchases == value,
                      onTap: () => setModal(() => purchases = value),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
