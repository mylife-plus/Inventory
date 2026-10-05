import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/notifications/in_app_notifications.dart';
import 'package:inventory_app/core/qr/qr_payload.dart';
import 'package:inventory_app/core/receipts/receipt_details_gate.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/local_photo.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<SaleLine>>(
  (ref) => CartNotifier(),
);

/// When set (e.g. from customer profile +), sell completes for this customer.
final sellCustomerProvider = StateProvider<Customer?>((ref) => null);

/// When set, confirming the cart updates this existing sale instead of creating one.
final editingSaleIdProvider = StateProvider<String?>((ref) => null);

/// Original lines of the sale being edited (for stock headroom while editing).
final editingSaleLinesProvider = StateProvider<List<SaleLine>?>((ref) => null);

class CartNotifier extends StateNotifier<List<SaleLine>> {
  CartNotifier() : super(const []);

  void clear() => state = const [];

  void replaceAll(List<SaleLine> lines) => state = List<SaleLine>.from(lines);

  void addItem(InventoryItem item, {double qty = 1}) {
    final i = state.indexWhere((l) => l.itemId == item.id);
    if (i >= 0) {
      final next = [...state];
      next[i] = next[i].copyWith(quantity: next[i].quantity + qty);
      state = next;
    } else {
      state = [
        ...state,
        SaleLine(
          itemId: item.id,
          title: item.title,
          unitPrice: item.price,
          quantity: qty,
          unit: item.unit,
          photoPath: item.photoPath,
        ),
      ];
    }
  }

  void mergeItems(Iterable<InventoryItem> items) {
    for (final item in items) {
      addItem(item);
    }
  }

  void setQty(String itemId, double qty) {
    if (qty <= 0) {
      state = state.where((l) => l.itemId != itemId).toList();
      return;
    }
    state = [
      for (final l in state)
        if (l.itemId == itemId) l.copyWith(quantity: qty) else l,
    ];
  }

  void removeItem(String itemId) {
    state = state.where((l) => l.itemId != itemId).toList();
  }
}

class SellPage extends ConsumerStatefulWidget {
  const SellPage({super.key});

  @override
  ConsumerState<SellPage> createState() => _SellPageState();
}

class _SellPageState extends ConsumerState<SellPage> {
  bool _busy = false;

  Future<void> _goCheckout() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final lines = List<SaleLine>.from(ref.read(cartProvider));
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(tProvider)('add_items_sell'))),
      );
      return;
    }

    // Editing an existing receipt — update lines and return to receipt.
    final editingId = ref.read(editingSaleIdProvider);
    if (editingId != null) {
      await _saveEditedSale(saleId: editingId, lines: lines);
      return;
    }

    // First-time sale: collect full shop receipt details before customer pick.
    final ready = await ensureShopReceiptDetails(context, ref);
    if (!ready || !mounted) return;

    final preset = ref.read(sellCustomerProvider);
    if (preset != null) {
      final customer = preset.id == '__guest__' ? null : preset;
      await _completeSale(lines: lines, customer: customer);
      return;
    }
    if (!mounted) return;
    context.push('/sell/customer?checkout=1');
  }

  Future<void> _saveEditedSale({
    required String saleId,
    required List<SaleLine> lines,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final sale = await ref.read(salesProvider.notifier).updateSaleLines(
            saleId: saleId,
            lines: lines,
          );
      ref.read(cartProvider.notifier).clear();
      _clearEditState();
      ref.read(sellCustomerProvider.notifier).state = null;
      if (!mounted) return;
      context.go('/sell/receipt/${sale.id}');
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeSale({
    required List<SaleLine> lines,
    Customer? customer,
  }) async {
    if (_busy) return;
    if (lines.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(tProvider)('add_items_sell'))),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final sale = await ref.read(salesProvider.notifier).completeSale(
            lines: lines,
            customer: customer,
          );
      final low =
          await ref.read(salesProvider.notifier).lowStockAfterSale(lines);
      ref.read(cartProvider.notifier).clear();
      ref.read(sellCustomerProvider.notifier).state = null;
      _clearEditState();
      if (!mounted) return;
      // Ask for shop details before opening the receipt (no QR underneath).
      await ensureShopReceiptDetails(context, ref);
      if (!mounted) return;
      context.go('/sell/receipt/${sale.id}');
      if (low.isNotEmpty) {
        // After navigation so the banner is visible on the next screen.
        notifyLowStockItems(ref, low);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _editStockBonus(String itemId) {
    final original = ref.read(editingSaleLinesProvider);
    if (original == null) return 0;
    return original
        .where((l) => l.itemId == itemId)
        .fold<double>(0, (s, l) => s + l.quantity);
  }

  void _clearEditState() {
    ref.read(editingSaleIdProvider.notifier).state = null;
    ref.read(editingSaleLinesProvider.notifier).state = null;
  }

  void _addToCart(InventoryItem item) {
    FocusScope.of(context).unfocus();
    final cart = ref.read(cartProvider);
    final inCart = cart
        .where((l) => l.itemId == item.id)
        .fold<double>(0, (s, l) => s + l.quantity);
    final maxAllowed = item.amount + _editStockBonus(item.id);
    if (inCart + 1 > maxAllowed + 1e-9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough stock for ${item.title} '
            '(have ${formatQty(maxAllowed)})',
          ),
        ),
      );
      return;
    }
    ref.read(cartProvider.notifier).addItem(item);
  }

  void _setQty(InventoryItem item, double q) {
    if (q <= 0) {
      ref.read(cartProvider.notifier).removeItem(item.id);
      return;
    }
    final maxAllowed = item.amount + _editStockBonus(item.id);
    final capped = q > maxAllowed ? maxAllowed : q;
    if (q > maxAllowed + 1e-9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough stock for ${item.title} '
            '(have ${formatQty(maxAllowed)})',
          ),
        ),
      );
    }
    ref.read(cartProvider.notifier).setQty(item.id, capped);
  }

  Future<void> _showAddProductsSheet() async {
    FocusScope.of(context).unfocus();
    await context.push<void>('/sell/add');
  }

  Future<void> _openScanner() async {
    FocusScope.of(context).unfocus();
    final scanned = await context.push<List<InventoryItem>>('/sell/scan');
    if (scanned == null || scanned.isEmpty || !mounted) return;
    for (final item in scanned) {
      _addToCart(item);
    }
  }

  Future<void> _adjustCartQty(SaleLine line) async {
    FocusScope.of(context).unfocus();
    final items = ref.read(inventoryItemsProvider).valueOrNull ?? [];
    var stock = items.where((i) => i.id == line.itemId).firstOrNull;
    stock ??= await ref.read(inventoryRepositoryProvider).getItem(line.itemId);
    if (!mounted) return;

    final maxQty =
        (stock?.amount ?? line.quantity) + _editStockBonus(line.itemId);
    final photo = (line.photoPath != null && line.photoPath!.isNotEmpty)
        ? line.photoPath
        : stock?.photoPath;
    final t = ref.read(tProvider);
    var qty = line.quantity;

    final applied = await showAppSheet<double>(
      context: context,
      heightFactor: 0.42,
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSheetHeader(title: line.title),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: LocalPhoto(
                              path: photo,
                              placeholderIcon: Icons.image_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t('amount')}: ${formatQty(maxQty)}',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              QtyStepper(
                                value: qty,
                                max: maxQty,
                                onChanged: (q) => setModal(() => qty = q),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ConfirmCancelBar(
                    confirmLabel: t('done'),
                    onCancel: () => Navigator.pop(ctx),
                    onConfirm: () => Navigator.pop(ctx, qty),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (applied != null && mounted) {
      if (stock != null) {
        _setQty(stock, applied);
      } else {
        ref.read(cartProvider.notifier).setQty(line.itemId, applied);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final cart = ref.watch(cartProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );
    final total = cart.fold<double>(0, (s, l) => s + l.lineTotal);
    final qty = cart.fold<double>(0, (s, l) => s + l.quantity);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: t('qr_scanner'),
          onPressed: _busy ? null : _openScanner,
          icon: AppIcon(
            AppAssets.qrScanner,
            size: 26,
            color: p.textSecondary,
          ),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 18, color: p.textSecondary),
            const SizedBox(width: 8),
            Text(t('sell_items')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t('add_items_sell'),
            onPressed: _busy ? null : _showAddProductsSheet,
            icon: Icon(
              Icons.add_rounded,
              size: 30,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: ConfirmCancelBar(
        confirmLabel: t('items_sold'),
        onCancel: () {
          if (_busy) return;
          FocusScope.of(context).unfocus();
          ref.read(cartProvider.notifier).clear();
          ref.read(sellCustomerProvider.notifier).state = null;
          _clearEditState();
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/inventory');
          }
        },
        onConfirm: () {
          if (_busy) return;
          _goCheckout();
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  t('total'),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.tr('cart_items_count', {'qty': formatQty(qty)}),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  money.format(total),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: cart.isEmpty
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _busy ? null : _showAddProductsSheet,
                    child: EmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: t('add_items_sell'),
                      subtitle: t('add_items_sell_sub'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: cart.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final line = cart[i];
                      final stock = (ref
                                  .watch(inventoryItemsProvider)
                                  .valueOrNull ??
                              [])
                          .where((it) => it.id == line.itemId)
                          .firstOrNull;
                      final photo =
                          (line.photoPath != null && line.photoPath!.isNotEmpty)
                              ? line.photoPath
                              : stock?.photoPath;
                      return _CartLineCard(
                        key: ValueKey('cart-${line.itemId}'),
                        line: line.copyWith(photoPath: photo),
                        money: money,
                        remaining: stock?.amount,
                        onEdit: () => _adjustCartQty(line),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    super.key,
    required this.line,
    required this.money,
    required this.onEdit,
    this.remaining,
  });

  final SaleLine line;
  final MoneyFormatter money;
  final VoidCallback onEdit;
  final double? remaining;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ProviderScope.containerOf(context).read(tProvider);
    final amountOnly = money.formatAmount(line.unitPrice);

    return MediaListCard(
      onTap: onEdit,
      thumb: CardThumb(
        path: line.photoPath,
        badge: formatQty(line.quantity),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        line.title,
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
                        unit: line.unit,
                      ),
                      if (remaining != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${t('amount')}: ${formatQty(remaining!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textMuted,
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: CardTotalLine(
                        value: money.format(line.lineTotal),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: t('edit_item'),
              onPressed: onEdit,
              icon: AppIcon(
                AppAssets.edit,
                size: 22,
                color: p.fabBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellProductCard extends StatelessWidget {
  const _SellProductCard({
    required this.item,
    required this.money,
    required this.cartQty,
    required this.maxQty,
    required this.onAdd,
    required this.onQty,
  });

  final InventoryItem item;
  final MoneyFormatter money;
  final double? cartQty;
  final double maxQty;
  final VoidCallback onAdd;
  final ValueChanged<double> onQty;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final amountOnly = money.formatAmount(item.price);

    return MediaListCard(
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
                child: cartQty == null
                    ? Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onAdd,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: p.fabBorder,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              'add',
                              style: TextStyle(
                                color: p.fabBorder,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      )
                    : QtyStepper(
                        key: ValueKey('qty-${item.id}'),
                        value: cartQty!,
                        max: maxQty,
                        onChanged: onQty,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class SellAddProductsPage extends ConsumerStatefulWidget {
  const SellAddProductsPage({super.key});

  @override
  ConsumerState<SellAddProductsPage> createState() =>
      _SellAddProductsPageState();
}

class _SellAddProductsPageState extends ConsumerState<SellAddProductsPage> {
  final _search = TextEditingController();
  String? _categoryFilter;
  bool _showSearch = false;
  _SellAddSort _sort = _SellAddSort.name;
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
                _sort == _SellAddSort.name || _sort == _SellAddSort.nameDesc;
            final priceSelected = _sort == _SellAddSort.priceHigh ||
                _sort == _SellAddSort.priceLow;
            final stockSelected = _sort == _SellAddSort.stockHigh ||
                _sort == _SellAddSort.stockLow;

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
                          label: nameSelected && _sort == _SellAddSort.nameDesc
                              ? t('sort_name_za')
                              : t('sort_name_az'),
                          icon: Icons.sort_by_alpha_rounded,
                          selected: nameSelected,
                          directionIcon: nameSelected
                              ? (_sort == _SellAddSort.name
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded)
                              : null,
                          onTap: () {
                            setState(() {
                              if (_sort == _SellAddSort.name) {
                                _sort = _SellAddSort.nameDesc;
                              } else if (_sort == _SellAddSort.nameDesc) {
                                _sort = _SellAddSort.name;
                              } else {
                                _sort = _SellAddSort.name;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        row(
                          label:
                              priceSelected && _sort == _SellAddSort.priceLow
                                  ? t('sort_lowest_price')
                                  : t('sort_highest_price'),
                          icon: Icons.payments_rounded,
                          selected: priceSelected,
                          directionIcon: priceSelected
                              ? (_sort == _SellAddSort.priceHigh
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded)
                              : null,
                          onTap: () {
                            setState(() {
                              if (_sort == _SellAddSort.priceHigh) {
                                _sort = _SellAddSort.priceLow;
                              } else if (_sort == _SellAddSort.priceLow) {
                                _sort = _SellAddSort.priceHigh;
                              } else {
                                _sort = _SellAddSort.priceHigh;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        row(
                          label:
                              stockSelected && _sort == _SellAddSort.stockLow
                                  ? t('sort_lowest_stock')
                                  : t('sort_highest_stock'),
                          icon: Icons.inventory_2_outlined,
                          selected: stockSelected,
                          directionIcon: stockSelected
                              ? (_sort == _SellAddSort.stockHigh
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded)
                              : null,
                          onTap: () {
                            setState(() {
                              if (_sort == _SellAddSort.stockHigh) {
                                _sort = _SellAddSort.stockLow;
                              } else if (_sort == _SellAddSort.stockLow) {
                                _sort = _SellAddSort.stockHigh;
                              } else {
                                _sort = _SellAddSort.stockHigh;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        row(
                          label: t('sort_most_recent'),
                          icon: Icons.schedule_rounded,
                          selected: _sort == _SellAddSort.recent,
                          directionIcon: null,
                          onTap: () {
                            setState(() => _sort = _SellAddSort.recent);
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
    final usedIds = items.map((i) => i.categoryId).whereType<String>().toSet();
    final usedCats = cats.where((c) => usedIds.contains(c.id)).toList()
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
      case _SellAddSort.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _SellAddSort.name:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _SellAddSort.nameDesc:
        list.sort(
            (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      case _SellAddSort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _SellAddSort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _SellAddSort.stockHigh:
        list.sort((a, b) => b.amount.compareTo(a.amount));
      case _SellAddSort.stockLow:
        list.sort((a, b) => a.amount.compareTo(b.amount));
    }
    return list;
  }

  void _addItem(InventoryItem item) {
    final cart = ref.read(cartProvider);
    final inCart = cart
        .where((l) => l.itemId == item.id)
        .fold<double>(0, (s, l) => s + l.quantity);
    final bonus = (ref.read(editingSaleLinesProvider) ?? const [])
        .where((l) => l.itemId == item.id)
        .fold<double>(0, (s, l) => s + l.quantity);
    final maxAllowed = item.amount + bonus;
    if (inCart + 1 > maxAllowed + 1e-9) return;
    ref.read(cartProvider.notifier).addItem(item);
  }

  void _setQty(InventoryItem item, double q) {
    final bonus = (ref.read(editingSaleLinesProvider) ?? const [])
        .where((l) => l.itemId == item.id)
        .fold<double>(0, (s, l) => s + l.quantity);
    final maxAllowed = item.amount + bonus;
    final capped = q > maxAllowed ? maxAllowed : q;
    ref.read(cartProvider.notifier).setQty(item.id, capped);
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
    final cart = ref.watch(cartProvider);
    final itemsAsync = ref.watch(inventoryItemsProvider);
    final catsAsync = ref.watch(categoriesProvider);
    final editLines = ref.watch(editingSaleLinesProvider) ?? const [];
    final cartQtyById = <String, double>{
      for (final l in cart) l.itemId: l.quantity,
    };

    double maxFor(InventoryItem item) {
      final bonus = editLines
          .where((l) => l.itemId == item.id)
          .fold<double>(0, (s, l) => s + l.quantity);
      return item.amount + bonus;
    }

    final cats = catsAsync.valueOrNull;
    final items = itemsAsync.valueOrNull;
    if (_categoryFilter != null &&
        _categoryFilter != '__uncat__' &&
        cats != null &&
        items != null) {
      final usedIds =
          items.map((i) => i.categoryId).whereType<String>().toSet();
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(t('add_items_sell')),
        actions: [
          IconButton(
            tooltip: t('search'),
            onPressed: () => setState(() => _showSearch = !_showSearch),
            icon: Icon(
              Icons.search_rounded,
              color: _showSearch ? p.neon : p.textSecondary,
            ),
          ),
          IconButton(
            tooltip: t('filter'),
            onPressed: _showFilterSheet,
            icon: Icon(
              Icons.filter_list_rounded,
              color: _categoryFilter != null ? p.neon : p.textSecondary,
            ),
          ),
          IconButton(
            tooltip: t('sort'),
            onPressed: _showSortSheet,
            icon: Icon(
              Icons.sort_rounded,
              color: _sort != _SellAddSort.name ? p.neon : p.textSecondary,
            ),
          ),
        ],
      ),
      bottomNavigationBar: ConfirmCancelBar(
        confirmLabel: t('done'),
        onCancel: () => context.pop(),
        onConfirm: () => context.pop(),
      ),
      body: Column(
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              data: (allItems) {
                final q = _search.text.trim().toLowerCase();
                final filtered = _sorted(
                  allItems.where((item) {
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

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
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
                        ),
                        if (open)
                          ...entry.value.map(
                            (item) => Padding(
                              key: ValueKey('sell-add-${item.id}'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SellProductCard(
                                item: item,
                                money: money,
                                cartQty: cartQtyById[item.id],
                                maxQty: maxFor(item),
                                onAdd: () => _addItem(item),
                                onQty: (q) => _setQty(item, q),
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

enum _SellAddSort {
  name,
  nameDesc,
  priceHigh,
  priceLow,
  stockHigh,
  stockLow,
  recent,
}

class SellScannerPage extends ConsumerStatefulWidget {
  const SellScannerPage({super.key});

  @override
  ConsumerState<SellScannerPage> createState() => _SellScannerPageState();
}

class _SellScannerPageState extends ConsumerState<SellScannerPage> {
  late final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;
  String? _lastRaw;
  DateTime? _lastScanAt;
  final List<InventoryItem> _pending = [];

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<InventoryItem?> _resolveItem(String id) async {
    final repo = ref.read(inventoryRepositoryProvider);
    final normalized = QrPayload.normalizeId(id) ?? id.trim();
    var item = await repo.getItem(normalized);
    if (item != null) return item;
    // Case-insensitive fallback against inventory list.
    final cached = ref.read(inventoryItemsProvider).valueOrNull;
    if (cached != null) {
      item = cached
          .where((i) => i.id.toLowerCase() == normalized.toLowerCase())
          .firstOrNull;
      if (item != null) return item;
    }
    final all = await repo.listItems();
    return all
        .where((i) => i.id.toLowerCase() == normalized.toLowerCase())
        .firstOrNull;
  }

  Future<void> _onDetect(String raw) async {
    if (_handling) return;
    final now = DateTime.now();
    if (_lastRaw == raw &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(seconds: 2)) {
      return;
    }
    _handling = true;
    _lastRaw = raw;
    _lastScanAt = now;
    try {
      final parsed = QrPayload.parse(raw);
      if (parsed.kind != QrKind.item || parsed.id == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Unrecognized QR: ${raw.length > 40 ? '${raw.substring(0, 40)}…' : raw}',
              ),
            ),
          );
        }
        return;
      }

      final item = await _resolveItem(parsed.id!);
      if (item == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.read(tProvider)('item_not_found_qr'))),
          );
        }
        return;
      }

      // Accumulate for multi-add; Done merges into cart.
      AppHaptics.medium();
      if (!mounted) return;
      setState(() => _pending.add(item));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${item.title} (+${_pending.where((i) => i.id == item.id).length})',
            ),
            duration: const Duration(milliseconds: 900),
          ),
        );
      }
    } finally {
      _handling = false;
    }
  }

  void _done() {
    final items = List<InventoryItem>.from(_pending);
    context.pop(items);
  }

  void _cancel() => context.pop();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final count = _pending.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: (capture) {
              final code = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .firstOrNull;
              if (code != null && code.isNotEmpty) {
                _onDetect(code);
              }
            },
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Camera error: ${error.errorCode}\nAllow camera access in Settings.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: _cancel,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
          if (count > 0)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, top: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.neon.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          IgnorePointer(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = (constraints.biggest.shortestSide * 0.62)
                      .clamp(180.0, 280.0);
                  return Container(
                    width: side,
                    height: side,
                    decoration: BoxDecoration(
                      border: Border.all(color: p.neon, width: 2.5),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 32,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: AccentButton(
                      label: t('close_scanner'),
                      color: p.cardElevated,
                      foreground: p.textPrimary,
                      onPressed: _cancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AccentButton(
                      label: count > 0 ? '${t('done')} ($count)' : t('done'),
                      onPressed: _done,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CustSort { name, recent }

class SelectCustomerPage extends ConsumerStatefulWidget {
  const SelectCustomerPage({super.key, this.checkout = false});

  /// When true, tapping a customer completes the sale.
  /// When false, only selects the customer and pops back to Sell.
  final bool checkout;

  @override
  ConsumerState<SelectCustomerPage> createState() => _SelectCustomerPageState();
}

class _SelectCustomerPageState extends ConsumerState<SelectCustomerPage> {
  bool _busy = false;
  bool _showSearch = false;
  final _search = TextEditingController();
  String? _filter; // phone | email | null=all
  _CustSort _sort = _CustSort.name;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _onPick(Customer? customer) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    if (!widget.checkout) {
      if (customer == null) {
        ref.read(sellCustomerProvider.notifier).state = Customer(
          id: '__guest__',
          name: ref.read(tProvider)('guest'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
      } else {
        ref.read(sellCustomerProvider.notifier).state = customer;
      }
      if (mounted) context.pop();
      return;
    }

    final lines = List<SaleLine>.from(ref.read(cartProvider));
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(tProvider)('add_items_sell'))),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final ready = await ensureShopReceiptDetails(context, ref);
      if (!ready || !mounted) return;

      final sale = await ref.read(salesProvider.notifier).completeSale(
            lines: lines,
            customer: customer,
          );
      final low =
          await ref.read(salesProvider.notifier).lowStockAfterSale(lines);
      ref.read(cartProvider.notifier).clear();
      ref.read(sellCustomerProvider.notifier).state = null;
      if (!mounted) return;
      context.go('/sell/receipt/${sale.id}');
      if (low.isNotEmpty) {
        notifyLowStockItems(ref, low);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final p = AppPalette.of(context);
    final customers = ref.watch(customersProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );
    final q = _search.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(t('select_customer')),
        actions: [
          IconButton(
            tooltip: t('search'),
            onPressed: () => setState(() => _showSearch = !_showSearch),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: t('filter'),
            onPressed: () async {
              final picked = await showAppSheet<String?>(
                context: context,
                heightFactor: 0.4,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSheetHeader(title: t('filter')),
                      AppRadioRow<String?>(
                        label: t('all'),
                        icon: Icons.people_outline_rounded,
                        value: null,
                        groupValue: _filter,
                        onChanged: (v) => Navigator.pop(ctx, v),
                      ),
                      AppRadioRow<String?>(
                        label: t('phone'),
                        icon: Icons.phone_rounded,
                        value: 'phone',
                        groupValue: _filter,
                        onChanged: (v) => Navigator.pop(ctx, v),
                      ),
                      AppRadioRow<String?>(
                        label: t('email'),
                        icon: Icons.email_outlined,
                        value: 'email',
                        groupValue: _filter,
                        onChanged: (v) => Navigator.pop(ctx, v),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
              setState(() => _filter = picked);
            },
            icon: const Icon(Icons.filter_list_rounded),
          ),
          IconButton(
            tooltip: t('sort'),
            onPressed: () async {
              final picked = await showAppSheet<_CustSort>(
                context: context,
                heightFactor: 0.36,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSheetHeader(title: t('sort')),
                      AppRadioRow<_CustSort>(
                        label: t('name'),
                        icon: Icons.sort_by_alpha_rounded,
                        value: _CustSort.name,
                        groupValue: _sort,
                        onChanged: (v) => Navigator.pop(ctx, v),
                      ),
                      AppRadioRow<_CustSort>(
                        label: t('sort_newest'),
                        icon: Icons.schedule_rounded,
                        value: _CustSort.recent,
                        groupValue: _sort,
                        onChanged: (v) => Navigator.pop(ctx, v),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
              if (picked != null) setState(() => _sort = picked);
            },
            icon: const Icon(Icons.sort_rounded),
          ),
          IconButton(
            tooltip: t('new_customer'),
            onPressed: _busy ? null : () => context.push('/customers/new'),
            icon: Icon(Icons.add_rounded, size: 28, color: p.textSecondary),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: t('search'),
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Expanded(
            child: customers.when(
              loading: () => const AppLoader(),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                var filtered = list.where((c) {
                  if (_filter == 'phone') {
                    return (c.phone?.trim().isNotEmpty ?? false);
                  }
                  if (_filter == 'email') {
                    return (c.email?.trim().isNotEmpty ?? false);
                  }
                  return true;
                }).where((c) {
                  if (q.isEmpty) return true;
                  return c.displayName.toLowerCase().contains(q) ||
                      (c.phone?.contains(q) ?? false) ||
                      (c.email?.toLowerCase().contains(q) ?? false);
                }).toList();
                if (_sort == _CustSort.name) {
                  filtered.sort(
                    (a, b) => a.displayName
                        .toLowerCase()
                        .compareTo(b.displayName.toLowerCase()),
                  );
                } else {
                  filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    FadeSlide(
                      child: CustomerListCard(
                        name: t('guest'),
                        money: money,
                        naStats: true,
                        onTap: _busy ? null : () => _onPick(null),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...filtered.map(
                      (c) => Padding(
                        key: ValueKey('pick-${c.id}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FadeSlide(
                          child: _SelectCustomerTile(
                            customer: c,
                            money: money,
                            onTap: _busy ? () {} : () => _onPick(c),
                          ),
                        ),
                      ),
                    ),
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

class _SelectCustomerTile extends ConsumerStatefulWidget {
  const _SelectCustomerTile({
    required this.customer,
    required this.money,
    required this.onTap,
  });

  final Customer customer;
  final MoneyFormatter money;
  final VoidCallback onTap;

  @override
  ConsumerState<_SelectCustomerTile> createState() =>
      _SelectCustomerTileState();
}

class _SelectCustomerTileState extends ConsumerState<_SelectCustomerTile> {
  late final Future<CustomerStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture =
        ref.read(customerRepositoryProvider).stats(widget.customer.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CustomerStats>(
      future: _statsFuture,
      builder: (context, snap) {
        return CustomerListCard(
          name: widget.customer.displayName,
          money: widget.money,
          stats: snap.data,
          photoPath: widget.customer.photoPath,
          contacts: widget.customer.allContacts,
          onTap: widget.onTap,
        );
      },
    );
  }
}
