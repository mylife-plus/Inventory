import 'package:flutter/material.dart';
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
import 'package:inventory_app/features/inventory/presentation/item_list_tools.dart';
import 'package:inventory_app/features/customers/presentation/customer_list_tools.dart';
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
      final sale = await ref
          .read(salesProvider.notifier)
          .updateSaleLines(saleId: saleId, lines: lines);
      ref.read(cartProvider.notifier).clear();
      _clearEditState();
      ref.read(sellCustomerProvider.notifier).state = null;
      if (!mounted) return;
      // Keep the origin (Items Sold list / customer) under the receipt.
      if (context.canPop()) {
        context.pushReplacement('/sell/receipt/${sale.id}');
      } else {
        context.go('/sell/receipt/${sale.id}');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      final sale = await ref
          .read(salesProvider.notifier)
          .completeSale(lines: lines, customer: customer);
      final low = await ref
          .read(salesProvider.notifier)
          .lowStockAfterSale(lines);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cancel. While editing a receipt this is a pure no-op on stock and on
  /// the sale: nothing is written and the edit state is dropped. The editor
  /// replaced the receipt in the history (see `_editSaleItems`), so popping
  /// returns to where the user was before the receipt (Items Sold list,
  /// customer purchases); with no history (receipt right after a sale) it
  /// goes to Inventory — the same place the receipt's own back leads.
  /// Outside editing the cart is discarded.
  void _cancel() {
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
      _warnStock(context, ref, item, maxAllowed);
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
      _warnStock(context, ref, item, maxAllowed);
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
                  // Cancel · Delete (center) · Check
                  ConfirmCancelBar(
                    onCancel: () => Navigator.pop(ctx),
                    onDelete: () => Navigator.pop(ctx, 0.0),
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
    final editing = ref.watch(editingSaleIdProvider) != null;

    // While editing a receipt, system back behaves exactly like Cancel so a
    // stale edit session can never be applied to a later sale.
    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
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
          // Left-aligned right after the scanner icon like every other
          // screen (only Add Items is centered, per the client).
          centerTitle: false,
          titleSpacing: 2,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 18,
                color: p.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(t('sell_items')),
            ],
          ),
          actions: [
            IconButton(
              tooltip: t('add_items_sell'),
              onPressed: _busy ? null : _showAddProductsSheet,
              icon: Icon(Icons.add_rounded, size: 30, color: p.textSecondary),
            ),
            const SizedBox(width: 4),
          ],
        ),
        bottomNavigationBar: ConfirmCancelBar(
          confirmLabel: t('items_sold'),
          onCancel: _cancel,
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
                        final stock =
                            (ref.watch(inventoryItemsProvider).valueOrNull ??
                                    [])
                                .where((it) => it.id == line.itemId)
                                .firstOrNull;
                        final photo =
                            (line.photoPath != null &&
                                line.photoPath!.isNotEmpty)
                            ? line.photoPath
                            : stock?.photoPath;
                        return _CartLineCard(
                          key: ValueKey('cart-${line.itemId}'),
                          line: line.copyWith(photoPath: photo),
                          money: money,
                          onEdit: () => _adjustCartQty(line),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cart line — same card as Inventory (badge = quantity in cart, tap = edit).
class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    super.key,
    required this.line,
    required this.money,
    required this.onEdit,
  });

  final SaleLine line;
  final MoneyFormatter money;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final amountOnly = money.formatAmount(line.unitPrice);

    return MediaListCard(
      onTap: onEdit,
      thumb: CardThumb(path: line.photoPath, badge: formatQty(line.quantity)),
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
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: CardTotalLine(value: money.format(line.lineTotal)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sell → Add items card — Inventory card layout; tap the card to add one,
/// "add" button when not in the cart, otherwise quantity box + delete.
class _SellProductCard extends StatelessWidget {
  const _SellProductCard({
    required this.item,
    required this.money,
    required this.cartQty,
    required this.maxQty,
    required this.addLabel,
    required this.onAdd,
    required this.onQty,
  });

  final InventoryItem item;
  final MoneyFormatter money;
  final double? cartQty;
  final double maxQty;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<double> onQty;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final amountOnly = money.formatAmount(item.price);
    final inCart = cartQty != null;

    // Same layout as the Inventory card (Figma): title + price top-left next
    // to the photo, the add / quantity control bottom-right (where Total is).
    return MediaListCard(
      onTap: onAdd,
      borderColor: inCart ? p.fabBorder : null,
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
              child: inCart
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CartQtyBox(
                          key: ValueKey('qty-${item.id}'),
                          value: cartQty!,
                          max: maxQty,
                          onChanged: onQty,
                        ),
                        const SizedBox(width: 6),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              AppHaptics.light();
                              onQty(0);
                            },
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: p.danger,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onAdd,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: p.fabBorder,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              addLabel,
                              style: TextStyle(
                                color: p.fabBorder,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small editable quantity box (blue border) used on Sell → Add items.
class _CartQtyBox extends StatefulWidget {
  const _CartQtyBox({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_CartQtyBox> createState() => _CartQtyBoxState();
}

class _CartQtyBoxState extends State<_CartQtyBox> {
  late final TextEditingController _ctrl = TextEditingController(
    text: formatQty(widget.value),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // Typing replaces the old number: select everything on focus.
        _selectAll();
        // The tap that focused the field places the caret afterwards.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focus.hasFocus) _selectAll();
        });
      } else {
        _commit();
      }
    });
  }

  void _selectAll() {
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _ctrl.text.length,
    );
  }

  @override
  void didUpdateWidget(covariant _CartQtyBox old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _ctrl.text = formatQty(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (v == null) {
      _ctrl.text = formatQty(widget.value);
      return;
    }
    if (v > widget.max + 1e-9) {
      // Let the page show the visible "not enough stock" notice + cap.
      _ctrl.text = formatQty(widget.max);
      widget.onChanged(v);
      return;
    }
    final next = v < 0 ? 0.0 : v;
    _ctrl.text = formatQty(next);
    if ((next - widget.value).abs() > 1e-9) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SizedBox(
      width: 48,
      height: 32,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        // Runs after the tap positioned the caret → select all again.
        onTap: _selectAll,
        onSubmitted: (_) => _focus.unfocus(),
        onTapOutside: (_) => _focus.unfocus(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: p.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: p.fabBorder, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: p.fabBorder, width: 1.6),
          ),
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
  SortState<ItemSortKey> _sort = kDefaultItemSort;
  final Set<String> _collapsed = {};

  /// Cart when the page opened — Cancel restores it.
  late final List<SaleLine> _snapshot = List<SaleLine>.from(
    ref.read(cartProvider),
  );
  bool _leaving = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _showSortSheet() async {
    final picked = await showSortSheet<ItemSortKey>(
      context: context,
      options: itemSortOptions(ref.read(tProvider)),
      current: _sort,
      defaultState: kDefaultItemSort,
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _showFilterSheet() async {
    final cats = ref.read(categoriesProvider).valueOrNull ?? [];
    final items = ref.read(inventoryItemsProvider).valueOrNull ?? [];
    final picked = await showItemFilterSheet(
      context,
      t: ref.read(tProvider),
      categories: usedCategories(cats, items),
      current: _categoryFilter,
    );
    if (picked != null && mounted) {
      setState(() => _categoryFilter = picked.categoryId);
    }
  }

  void _leave() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  void _cancel() {
    ref.read(cartProvider.notifier).replaceAll(_snapshot);
    _leave();
  }

  double _maxFor(InventoryItem item) {
    final bonus = (ref.read(editingSaleLinesProvider) ?? const [])
        .where((l) => l.itemId == item.id)
        .fold<double>(0, (s, l) => s + l.quantity);
    return item.amount + bonus;
  }

  void _addItem(InventoryItem item) {
    FocusManager.instance.primaryFocus?.unfocus();
    final inCart = ref
        .read(cartProvider)
        .where((l) => l.itemId == item.id)
        .fold<double>(0, (s, l) => s + l.quantity);
    final maxAllowed = _maxFor(item);
    if (inCart + 1 > maxAllowed + 1e-9) {
      _warnStock(context, ref, item, maxAllowed);
      return;
    }
    AppHaptics.selection();
    ref.read(cartProvider.notifier).addItem(item);
  }

  void _setQty(InventoryItem item, double q) {
    final maxAllowed = _maxFor(item);
    if (q > maxAllowed + 1e-9) _warnStock(context, ref, item, maxAllowed);
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
    ref.watch(editingSaleLinesProvider);
    final cartQtyById = <String, double>{
      for (final l in cart) l.itemId: l.quantity,
    };
    final cartTotal = cart.fold<double>(0, (s, l) => s + l.lineTotal);
    final cartCount = cart.fold<double>(0, (s, l) => s + l.quantity);

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          // Client: "Add Items" is centered (exception to left-aligned titles).
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(AppAssets.inventory, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(t('add_items')),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ConfirmCancelBar(
          onCancel: _cancel,
          onConfirm: _leave,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
                    t.tr('cart_items_count', {'qty': formatQty(cartCount)}),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    money.format(cartTotal),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: ListActionIconsRow(
                onSort: _showSortSheet,
                onFilter: _showFilterSheet,
                onSearch: () => setState(() => _showSearch = !_showSearch),
                sortActive: _sort != kDefaultItemSort,
                filterActive: _categoryFilter != null,
                searchActive: _showSearch || _search.text.trim().isNotEmpty,
              ),
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
                data: (allItems) {
                  final q = _search.text.trim().toLowerCase();
                  final filtered = sortItems(
                    allItems.where((item) {
                      final matchQ =
                          q.isEmpty || item.title.toLowerCase().contains(q);
                      final matchC =
                          _categoryFilter == null ||
                          item.categoryId == _categoryFilter;
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
                    ..sort(
                      (a, b) =>
                          a.key.toLowerCase().compareTo(b.key.toLowerCase()),
                    );

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                                  maxQty: _maxFor(item),
                                  addLabel: t('add').toLowerCase(),
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
      ),
    );
  }
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

  /// Older labels with a link only encoded the URL (no item id). Match the
  /// scanned URL against the items' saved label links.
  Future<InventoryItem?> _resolveByLink(String raw) async {
    final key = QrPayload.linkKey(raw);
    if (key.isEmpty) return null;
    final items =
        ref.read(inventoryItemsProvider).valueOrNull ??
        await ref.read(inventoryRepositoryProvider).listItems();
    final matches = items
        .where(
          (i) =>
              (i.qrLink ?? '').trim().isNotEmpty &&
              QrPayload.linkKey(i.qrLink!) == key,
        )
        .toList();
    return matches.length == 1 ? matches.first : null;
  }

  Future<void> _onDetect(String raw) async {
    if (_handling) return;
    final now = DateTime.now();
    // The camera reports the same code many times per second while it stays
    // in view: add it once, and again only after it left the view briefly.
    final sameCode =
        _lastRaw == raw &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(milliseconds: 1500);
    _lastRaw = raw;
    _lastScanAt = now;
    if (sameCode) return;
    _handling = true;
    try {
      final parsed = QrPayload.parse(raw);
      final item =
          (parsed.kind == QrKind.item && parsed.id != null
              ? await _resolveItem(parsed.id!)
              : null) ??
          await _resolveByLink(raw);
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
      // Listed under the scanner right away (no snackbar over the list).
      setState(() => _pending.add(item));
    } finally {
      _handling = false;
    }
  }

  void _done() {
    final items = List<InventoryItem>.from(_pending);
    context.pop(items);
  }

  void _cancel() => context.pop();

  /// Scanned items grouped by id (scan order kept) with their counts.
  List<(InventoryItem, int)> get _grouped {
    final order = <String>[];
    final byId = <String, InventoryItem>{};
    final counts = <String, int>{};
    for (final item in _pending) {
      if (!byId.containsKey(item.id)) order.add(item.id);
      byId[item.id] = item;
      counts[item.id] = (counts[item.id] ?? 0) + 1;
    }
    return [for (final id in order) (byId[id]!, counts[id]!)];
  }

  void _removeScanned(String itemId) {
    AppHaptics.light();
    setState(() => _pending.removeWhere((i) => i.id == itemId));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final count = _pending.length;
    final grouped = _grouped;
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: t('close_scanner'),
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppAssets.qrScanner, size: 22, color: p.textSecondary),
            const SizedBox(width: 8),
            Text(t('qr_scanner')),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Client: the camera takes at most 1/3 of the page height; the
            // scanned items list fills the rest.
            final scannerHeight = constraints.maxHeight / 3;
            final frame = (scannerHeight * 0.78).clamp(120.0, 240.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: SizedBox(
                    height: scannerHeight - 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Colors.black),
                          MobileScanner(
                            controller: _scanner,
                            fit: BoxFit.cover,
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
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    ref.read(tProvider).tr('camera_error', {'code': '${error.errorCode}'}),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              );
                            },
                          ),
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                width: frame,
                                height: frame,
                                decoration: BoxDecoration(
                                  border: Border.all(color: p.neon, width: 2.5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: [
                      Text(
                        t('scanned_items'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: p.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: p.neon.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: p.neon,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: grouped.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 36,
                                  color: p.textMuted,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t('scan_items_hint'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: p.textMuted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          itemCount: grouped.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final (item, n) = grouped[i];
                            return FadeSlide(
                              key: ValueKey('scanned-${item.id}'),
                              child: _ScannedItemCard(
                                item: item,
                                count: n,
                                money: money,
                                onRemove: () => _removeScanned(item.id),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                          label: count > 0
                              ? '${t('done')} ($count)'
                              : t('done'),
                          onPressed: _done,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Scanned item row under the camera — same card as the cart / inventory.
class _ScannedItemCard extends StatelessWidget {
  const _ScannedItemCard({
    required this.item,
    required this.count,
    required this.money,
    required this.onRemove,
  });

  final InventoryItem item;
  final int count;
  final MoneyFormatter money;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return MediaListCard(
      thumb: CardThumb(path: item.photoPath, badge: '$count'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    amount: money.formatAmount(item.price).trim(),
                    symbol: money.symbol,
                    unit: item.unit,
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: CardTotalLine(
                        value: money.format(item.price * count),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: p.danger,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SelectCustomerPage extends ConsumerStatefulWidget {
  const SelectCustomerPage({super.key, this.checkout = false, this.saleId});

  /// When true, tapping a customer completes the sale.
  /// When false, only selects the customer and pops back to Sell.
  final bool checkout;

  /// When set (from a receipt), picking re-assigns that sale's customer and
  /// pops with `true`.
  final String? saleId;

  @override
  ConsumerState<SelectCustomerPage> createState() => _SelectCustomerPageState();
}

class _SelectCustomerPageState extends ConsumerState<SelectCustomerPage> {
  bool _busy = false;
  bool _showSearch = false;
  final _search = TextEditingController();
  SortState<CustomerSortKey> _sort = kDefaultCustomerSort;
  CustomerFilter _filter = const CustomerFilter();
  Map<String, CustomerStats> _stats = {};
  String _statsKey = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadStats(List<Customer> list) async {
    final repo = ref.read(customerRepositoryProvider);
    final next = <String, CustomerStats>{};
    for (final c in list) {
      next[c.id] = await repo.stats(c.id);
    }
    if (!mounted) return;
    setState(() => _stats = next);
  }

  Future<void> _showSortSheet() async {
    final picked = await showSortSheet<CustomerSortKey>(
      context: context,
      options: customerSortOptions(ref.read(tProvider)),
      current: _sort,
      defaultState: kDefaultCustomerSort,
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _showFilterSheet() async {
    final picked = await showCustomerFilterSheet(
      context,
      t: ref.read(tProvider),
      current: _filter,
      customFieldLabels: customFieldLabels(
        ref.read(customersProvider).valueOrNull ?? const [],
      ),
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  Future<void> _onPick(Customer? customer) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final saleId = widget.saleId;
    if (saleId != null) {
      setState(() => _busy = true);
      try {
        await ref
            .read(salesProvider.notifier)
            .updateSaleCustomer(saleId, customer);
        if (mounted) context.pop(true);
      } catch (e) {
        debugPrint('Update sale customer failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.read(tProvider)('save_failed'))),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

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

      final sale = await ref
          .read(salesProvider.notifier)
          .completeSale(lines: lines, customer: customer);
      final low = await ref
          .read(salesProvider.notifier)
          .lowStockAfterSale(lines);
      ref.read(cartProvider.notifier).clear();
      ref.read(sellCustomerProvider.notifier).state = null;
      ref.read(editingSaleIdProvider.notifier).state = null;
      ref.read(editingSaleLinesProvider.notifier).state = null;
      if (!mounted) return;
      context.go('/sell/receipt/${sale.id}');
      if (low.isNotEmpty) {
        notifyLowStockItems(ref, low);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            tooltip: t('new_customer'),
            onPressed: _busy ? null : () => context.push('/customers/new'),
            icon: Icon(Icons.add_rounded, size: 28, color: p.textSecondary),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ListActionIconsRow(
              onSort: _showSortSheet,
              onFilter: _showFilterSheet,
              onSearch: () => setState(() => _showSearch = !_showSearch),
              sortActive: _sort != kDefaultCustomerSort,
              filterActive: _filter.isActive,
              searchActive: _showSearch || _search.text.trim().isNotEmpty,
            ),
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
            child: customers.when(
              loading: () => const AppLoader(),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final key = list.map((c) => c.id).join(',');
                if (key != _statsKey) {
                  _statsKey = key;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _loadStats(list);
                  });
                }
                final filtered = sortCustomers(
                  list
                      .where(
                        (c) =>
                            _filter.matches(c, _stats[c.id]) &&
                            customerMatchesQuery(c, q),
                      )
                      .toList(),
                  _sort,
                  _stats,
                );

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
                          child: SelectCustomerTile(
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

class SelectCustomerTile extends ConsumerStatefulWidget {
  const SelectCustomerTile({
    super.key,
    required this.customer,
    required this.money,
    required this.onTap,
    this.contactsInteractive = true,
  });

  final Customer customer;
  final MoneyFormatter money;
  final VoidCallback onTap;

  /// False on the Send Receipt page: icons are shown but don't launch apps.
  final bool contactsInteractive;

  @override
  ConsumerState<SelectCustomerTile> createState() => SelectCustomerTileState();
}

class SelectCustomerTileState extends ConsumerState<SelectCustomerTile> {
  late final Future<CustomerStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = ref
        .read(customerRepositoryProvider)
        .stats(widget.customer.id);
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
          contactsInteractive: widget.contactsInteractive,
          onTap: widget.onTap,
        );
      },
    );
  }
}

/// "Not enough stock" warning as a top banner — always visible, even while
/// the number keyboard is open (a SnackBar sat behind it).
void _warnStock(
  BuildContext context,
  WidgetRef ref,
  InventoryItem item,
  double have,
) {
  AppHaptics.medium();
  showTopNotice(
    context,
    ref.read(tProvider).tr('not_enough_stock', {
      'item': item.title,
      'qty': formatQty(have),
    }),
  );
}
