import 'package:flutter/material.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';

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

/// Icon used for user-defined custom contact fields (filter + profile).
const IconData kCustomFieldIcon = Icons.label_rounded;

class CustomerFilter {
  const CustomerFilter({
    this.contacts = const {},
    this.customFields = const {},
    this.purchases = PurchaseFilter.all,
  });

  /// Customer must have every selected contact option.
  final Set<ContactKind> contacts;

  /// Custom field labels (lower-cased) the customer must have filled in.
  final Set<String> customFields;
  final PurchaseFilter purchases;

  bool get isActive =>
      contacts.isNotEmpty ||
      customFields.isNotEmpty ||
      purchases != PurchaseFilter.all;

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
    for (final label in customFields) {
      final ok = c.customFields.any(
        (f) => f.label.trim().toLowerCase() == label && has(f.value),
      );
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

/// Distinct custom field labels used across [customers] (first spelling
/// wins), sorted A–Z — offered as extra contact options in the filter.
List<String> customFieldLabels(Iterable<Customer> customers) {
  final byKey = <String, String>{};
  for (final c in customers) {
    for (final f in c.customFields) {
      final label = f.label.trim();
      if (label.isEmpty) continue;
      byKey.putIfAbsent(label.toLowerCase(), () => label);
    }
  }
  return byKey.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

Widget _contactKindIcon(ContactKind k, {double size = 22}) => switch (k) {
      ContactKind.phone => Icon(
          Icons.phone_rounded,
          size: size,
          color: const Color(0xFF34C759),
        ),
      ContactKind.email => AppIcon(AppAssets.email, size: size),
      ContactKind.whatsapp => AppIcon(AppAssets.whatsapp, size: size),
      ContactKind.facebook => AppIcon(AppAssets.facebook, size: size),
      ContactKind.instagram => AppIcon(AppAssets.instagram, size: size),
      ContactKind.linkedin => AppIcon(AppAssets.linkedin, size: size),
      ContactKind.telegram => AppIcon(AppAssets.telegram, size: size),
    };

/// One selectable contact option in the filter: a built-in kind or a
/// custom field label.
@immutable
class _ContactOption {
  const _ContactOption.kind(ContactKind this.kind) : custom = null;
  const _ContactOption.custom(String this.custom) : kind = null;

  final ContactKind? kind;
  final String? custom;

  String label(S t) => kind != null ? t(kind!.name) : custom!;

  Widget icon(AppPalette p, {double size = 22}) => kind != null
      ? _contactKindIcon(kind!, size: size)
      : Icon(kCustomFieldIcon, size: size, color: p.neon);
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
///
/// Contact options are picked from a dropdown; each pick is listed below as
/// a removable row. [customFieldLabels] (see [customFieldLabels]) adds the
/// user's own contact fields to the dropdown.
Future<CustomerFilter?> showCustomerFilterSheet(
  BuildContext context, {
  required S t,
  required CustomerFilter current,
  List<String> customFieldLabels = const [],
}) {
  final contacts = {...current.contacts};
  final custom = {...current.customFields};
  var purchases = current.purchases;
  final customByKey = {
    for (final l in customFieldLabels) l.trim().toLowerCase(): l.trim(),
  };
  // Keep previously selected custom labels visible even if no longer used.
  for (final key in custom) {
    customByKey.putIfAbsent(key, () => key);
  }
  final allOptions = <_ContactOption>[
    for (final k in ContactKind.values) _ContactOption.kind(k),
    for (final l in customByKey.values) _ContactOption.custom(l),
  ];
  bool isSelected(_ContactOption o) => o.kind != null
      ? contacts.contains(o.kind)
      : custom.contains(o.custom!.toLowerCase());

  return showAppSheet<CustomerFilter>(
    context: context,
    alignTop: true,
    heightFactor: 0.7,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) {
        final p = AppPalette.of(ctx);
        final selected = allOptions.where(isSelected).toList();
        final remaining = allOptions.where((o) => !isSelected(o)).toList();

        Future<void> openDropdown(BuildContext anchorCtx) async {
          if (remaining.isEmpty) return;
          final box = anchorCtx.findRenderObject() as RenderBox?;
          final overlay =
              Overlay.of(anchorCtx).context.findRenderObject() as RenderBox?;
          if (box == null || overlay == null) return;
          final topLeft = box.localToGlobal(
            Offset(0, box.size.height),
            ancestor: overlay,
          );
          final bottomRight = box.localToGlobal(
            box.size.bottomRight(Offset.zero),
            ancestor: overlay,
          );
          final picked = await showMenu<_ContactOption>(
            context: anchorCtx,
            position: RelativeRect.fromRect(
              Rect.fromPoints(topLeft, bottomRight),
              Offset.zero & overlay.size,
            ),
            color: p.cardElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: p.stroke),
            ),
            constraints: BoxConstraints(
              minWidth: box.size.width,
              maxWidth: box.size.width,
              maxHeight: 320,
            ),
            items: [
              for (final o in remaining)
                PopupMenuItem(
                  value: o,
                  child: Row(
                    children: [
                      SizedBox(width: 26, child: Center(child: o.icon(p))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          o.label(t),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
          if (picked == null) return;
          AppHaptics.selection();
          setModal(() {
            if (picked.kind != null) {
              contacts.add(picked.kind!);
            } else {
              custom.add(picked.custom!.toLowerCase());
            }
          });
        }

        void remove(_ContactOption o) {
          AppHaptics.light();
          setModal(() {
            if (o.kind != null) {
              contacts.remove(o.kind);
            } else {
              custom.remove(o.custom!.toLowerCase());
            }
          });
        }

        return AppFilterSheet(
          onReset: () => Navigator.pop(ctx, const CustomerFilter()),
          onApply: () => Navigator.pop(
            ctx,
            CustomerFilter(
              contacts: contacts,
              customFields: custom,
              purchases: purchases,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFilterSection(
                title: t('contact_options'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (anchorCtx) => _FilterDropdownField(
                        hint: t('add_contact_option'),
                        enabled: remaining.isNotEmpty,
                        onTap: () => openDropdown(anchorCtx),
                      ),
                    ),
                    for (final o in selected) ...[
                      const SizedBox(height: 8),
                      _SelectedContactRow(
                        key: ValueKey(o.kind?.name ?? 'custom:${o.custom}'),
                        icon: o.icon(p),
                        label: o.label(t),
                        onRemove: () => remove(o),
                      ),
                    ],
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
        );
      },
    ),
  );
}

/// Dropdown-style field (same look as the app's inputs).
class _FilterDropdownField extends StatelessWidget {
  const _FilterDropdownField({
    required this.hint,
    required this.enabled,
    required this.onTap,
  });

  final String hint;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () {
                AppHaptics.selection();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: p.cardElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.stroke),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hint,
                  style: TextStyle(
                    color: enabled ? p.textSecondary : p.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down_rounded,
                color: enabled ? p.textSecondary : p.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedContactRow extends StatelessWidget {
  const _SelectedContactRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  final Widget icon;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return FadeSlide(
      offset: 8,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: p.fabBorder.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.fabBorder, width: 1.2),
        ),
        child: Row(
          children: [
            SizedBox(width: 26, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: p.textPrimary,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, color: p.textMuted, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
