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

/// Nov 11 client review: Sell → Add items, quantity keyboard open, tapping
/// another item must only close the keyboard (not add the item).
final _now = DateTime(2026, 11, 11);
final _items = [
  InventoryItem(
    id: 'a',
    title: 'Bread',
    price: 2.5,
    amount: 10,
    createdAt: _now,
    updatedAt: _now,
  ),
  InventoryItem(
    id: 'b',
    title: 'Cheese',
    price: 3.5,
    amount: 10,
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

Future<ProviderContainer> _open(WidgetTester tester) async {
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
  container.read(cartProvider.notifier).replaceAll(const [
    SaleLine(itemId: 'a', title: 'Bread', unitPrice: 2.5, quantity: 1),
  ]);
  final router = GoRouter(
    initialLocation: '/sell',
    routes: [
      GoRoute(
        path: '/sell',
        builder: (_, _) => const Scaffold(body: Text('sell')),
      ),
      GoRoute(path: '/sell/add', builder: (_, _) => const SellAddProductsPage()),
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
  return container;
}

bool _textFocused() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null &&
      (ctx.widget is EditableText ||
          ctx.findAncestorWidgetOfExactType<EditableText>() != null);
}

Finder _qtyField(String id) => find.descendant(
      of: find.byKey(ValueKey('qty-$id')),
      matching: find.byType(TextField),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('first tap on another item only closes the quantity keyboard',
      (tester) async {
    final c = await _open(tester);
    await tester.tap(_qtyField('a'));
    await tester.pump();
    expect(_textFocused(), isTrue);

    await tester.tap(find.text('Cheese'));
    await tester.pumpAndSettle();
    expect(_textFocused(), isFalse, reason: 'keyboard closed');
    expect(c.read(cartProvider).map((l) => l.itemId), ['a'],
        reason: 'Cheese must NOT be added by the dismiss tap');

    // Keyboard is gone: the next tap adds as before.
    await tester.tap(find.text('Cheese'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).map((l) => l.itemId), ['a', 'b']);
  });

  testWidgets('typed quantity is kept when the dismiss tap lands elsewhere',
      (tester) async {
    final c = await _open(tester);
    await tester.tap(_qtyField('a'));
    await tester.pump();
    await tester.enterText(_qtyField('a'), '4');
    await tester.tap(find.text('Cheese'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).single.quantity, 4);
    expect(c.read(cartProvider).single.itemId, 'a');
  });

  testWidgets('delete while the keyboard is open only closes it first',
      (tester) async {
    final c = await _open(tester);
    await tester.tap(_qtyField('a'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).length, 1);
    expect(_textFocused(), isFalse);
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider), isEmpty);
  });

  testWidgets('without a keyboard a tap on an item adds it right away',
      (tester) async {
    final c = await _open(tester);
    await tester.tap(find.text('Cheese'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).map((l) => l.itemId), ['a', 'b']);
  });
}
