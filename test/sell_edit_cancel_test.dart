import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/sell/presentation/sell_page.dart';

/// Oct 9 client review: receipt Edit -> Add Items -> remove / change items
/// -> Cancel (or system Back) must leave the edited cart exactly as it was.
/// The cart snapshot used to be a lazy `late final`, so it was taken at
/// Cancel time (already modified) and Cancel "removed" the items.
final _now = DateTime(2026, 10, 9);
final _items = [
  InventoryItem(
    id: 'a',
    title: 'Organic',
    price: 12.9,
    amount: 4,
    createdAt: _now,
    updatedAt: _now,
  ),
  InventoryItem(
    id: 'b',
    title: 'Cheese',
    price: 3.5,
    amount: 5,
    createdAt: _now,
    updatedAt: _now,
  ),
];

class _Items extends InventoryItemsNotifier {
  @override
  Future<List<InventoryItem>> build() async => _items;
}

class _Settings extends ShopSettingsNotifier {
  @override
  Future<ShopSettings> build() async =>
      const ShopSettings(companyName: 'Demo Shop');
}

class _Cats extends CategoriesNotifier {
  @override
  Future<List<Category>> build() async => const [];
}

const _saleLines = [
  SaleLine(itemId: 'a', title: 'Organic', unitPrice: 12.9, quantity: 2),
  SaleLine(itemId: 'b', title: 'Cheese', unitPrice: 3.5, quantity: 1),
];

Future<ProviderContainer> _openAddItems(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      tProvider.overrideWithValue(S('en')),
      inventoryItemsProvider.overrideWith(_Items.new),
      shopSettingsProvider.overrideWith(_Settings.new),
      categoriesProvider.overrideWith(_Cats.new),
    ],
  );
  addTearDown(container.dispose);
  // Same state the receipt's Edit button sets up.
  container.read(cartProvider.notifier).replaceAll(_saleLines);
  container.read(editingSaleIdProvider.notifier).state = 'sale-1';
  container.read(editingSaleLinesProvider.notifier).state = _saleLines;

  final router = GoRouter(
    initialLocation: '/sell',
    routes: [
      GoRoute(
        path: '/sell',
        builder: (_, _) => const Scaffold(body: Text('sell editor')),
      ),
      GoRoute(
        path: '/sell/add',
        builder: (_, _) => const SellAddProductsPage(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  router.push('/sell/add');
  await tester.pumpAndSettle();
  expect(find.byType(SellAddProductsPage), findsOneWidget);
  return container;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Add Items Cancel restores removed items and quantities',
      (tester) async {
    final c = await _openAddItems(tester);
    // User removes one item and changes the other's quantity.
    c.read(cartProvider.notifier).removeItem('b');
    c.read(cartProvider.notifier).setQty('a', 3);
    await tester.pump();
    expect(c.read(cartProvider).length, 1);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SellAddProductsPage), findsNothing);
    expect(c.read(cartProvider), _saleLines);
    // Still editing the same receipt; nothing else touched.
    expect(c.read(editingSaleIdProvider), 'sale-1');
    expect(c.read(editingSaleLinesProvider), _saleLines);
  });

  testWidgets('Add Items system Back restores the cart too', (tester) async {
    final c = await _openAddItems(tester);
    c.read(cartProvider.notifier).removeItem('a');
    c.read(cartProvider.notifier).removeItem('b');
    await tester.pump();
    expect(c.read(cartProvider), isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(SellAddProductsPage), findsNothing);
    expect(c.read(cartProvider), _saleLines);
  });

  testWidgets('Add Items Cancel with no changes keeps the cart as is',
      (tester) async {
    final c = await _openAddItems(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider), _saleLines);
  });
}
