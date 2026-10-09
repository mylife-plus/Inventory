import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/data/resale_draft.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/sell/presentation/sell_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oct 9 client review (#5): Items Sold → receipt → Edit → Continue undoes
/// the sale (stock back, receipt gone), puts items + customer in the Sell
/// cart, and completing again re-creates the receipt (same number, date).
/// Cancel anywhere in that flow never removes items from the cart.
final _date = DateTime(2026, 10, 1, 9, 30);

final _alice = Customer(id: 'c1', name: 'Alice', createdAt: _date);

class _Db {
  final stock = <String, double>{'a': 4, 'b': 5};
  final sales = <String, Sale>{};
  var ids = 0;
}

InventoryItem _item(String id, double amount) => InventoryItem(
  id: id,
  title: id == 'a' ? 'Organic' : 'Cheese',
  price: id == 'a' ? 12.9 : 3.5,
  amount: amount,
  createdAt: _date,
  updatedAt: _date,
);

class _Inventory implements InventoryRepository {
  _Inventory(this.db);
  final _Db db;

  @override
  Future<List<InventoryItem>> listItems({
    String? query,
    String? categoryId,
  }) async => [for (final e in db.stock.entries) _item(e.key, e.value)];

  @override
  Future<InventoryItem?> getItem(String id) async =>
      db.stock.containsKey(id) ? _item(id, db.stock[id]!) : null;

  @override
  Future<List<Category>> listCategories() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Customers implements CustomerRepository {
  @override
  Future<List<Customer>> list() async => [_alice];

  @override
  Future<Customer?> get(String id) async => id == _alice.id ? _alice : null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Same rules as the SQLite repository: create deducts stock, void gives
/// it back and removes the receipt.
class _Sales implements SaleRepository {
  _Sales(this.db);
  final _Db db;

  @override
  Future<Sale?> get(String id) async => db.sales[id];

  @override
  Future<List<Sale>> list() async => db.sales.values.toList();

  @override
  Future<Sale> createSale({
    required List<SaleLine> lines,
    Customer? customer,
    String? id,
    DateTime? createdAt,
  }) async {
    for (final l in lines) {
      if ((db.stock[l.itemId] ?? 0) + 1e-9 < l.quantity) {
        throw StateError('Not enough stock for ${l.title}');
      }
    }
    final saleId = id ?? 'sale-${++db.ids}-0000';
    if (db.sales.containsKey(saleId)) throw StateError('duplicate id');
    for (final l in lines) {
      db.stock[l.itemId] = db.stock[l.itemId]! - l.quantity;
    }
    final guest = customer == null || customer.id == '__guest__';
    return db.sales[saleId] = Sale(
      id: saleId,
      customerId: guest ? null : customer.id,
      customerName: guest ? 'Guest' : customer.displayName,
      total: lines.fold(0.0, (s, l) => s + l.lineTotal),
      createdAt: createdAt ?? DateTime.now(),
      lines: lines,
    );
  }

  @override
  Future<void> voidSale(String saleId) async {
    final sale = db.sales.remove(saleId);
    if (sale == null) return;
    for (final l in sale.lines) {
      if (db.stock.containsKey(l.itemId)) {
        db.stock[l.itemId] = db.stock[l.itemId]! + l.quantity;
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Settings extends ShopSettingsNotifier {
  @override
  Future<ShopSettings> build() async =>
      const ShopSettings(companyName: 'Demo Shop');
}

ProviderContainer _container(_Db db) {
  final c = ProviderContainer(
    overrides: [
      tProvider.overrideWithValue(S('en')),
      inventoryRepositoryProvider.overrideWithValue(_Inventory(db)),
      customerRepositoryProvider.overrideWithValue(_Customers()),
      saleRepositoryProvider.overrideWithValue(_Sales(db)),
      shopSettingsProvider.overrideWith(_Settings.new),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

const _lines = [
  SaleLine(itemId: 'a', title: 'Organic', unitPrice: 12.9, quantity: 2),
  SaleLine(itemId: 'b', title: 'Cheese', unitPrice: 3.5, quantity: 1),
];

Future<Sale> _sold(ProviderContainer c, {Customer? customer}) async {
  await c.read(salesProvider.future);
  return c
      .read(salesProvider.notifier)
      .completeSale(lines: _lines, customer: customer);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Continue undoes the sale and loads items + customer', () async {
    final db = _Db();
    final c = _container(db);
    final sale = await _sold(c, customer: _alice);
    expect(db.stock, {'a': 2, 'b': 4});

    await startResale(c.read, sale, guestName: 'Guest');

    // Stock restored, receipt removed (no longer in totals / turnover).
    expect(db.stock, {'a': 4, 'b': 5});
    expect(db.sales, isEmpty);
    expect(c.read(salesProvider).value, isEmpty);
    // Items + customer on the normal Sell page.
    expect(c.read(cartProvider), _lines);
    expect(c.read(sellCustomerProvider)?.id, 'c1');
    expect(c.read(editingSaleIdProvider), isNull);
    // Saved for app kill.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ResaleDraftNotifier.prefKey), contains(sale.id));
  });

  test('Guest receipt carries over as Guest', () async {
    final c = _container(_Db());
    final sale = await _sold(c);
    await startResale(c.read, sale, guestName: 'Guest');
    expect(c.read(sellCustomerProvider)?.id, '__guest__');
  });

  test(
    'Completing again re-creates the receipt once, same number + date',
    () async {
      final db = _Db();
      final c = _container(db);
      final sale = await _sold(c, customer: _alice);
      final original = db.sales[sale.id]!;
      final backdated = Sale(
        id: original.id,
        customerId: original.customerId,
        customerName: original.customerName,
        total: original.total,
        createdAt: _date,
        lines: original.lines,
      );
      db.sales[sale.id] = backdated;

      await startResale(c.read, backdated, guestName: 'Guest');
      // User changes the cart: 1 Organic only.
      c.read(cartProvider.notifier).removeItem('b');
      c.read(cartProvider.notifier).setQty('a', 1);

      final again = await c
          .read(salesProvider.notifier)
          .completeSale(
            lines: c.read(cartProvider),
            customer: c.read(sellCustomerProvider),
          );
      expect(again.id, sale.id);
      expect(again.createdAt, _date);
      expect(again.customerId, 'c1');
      expect(db.sales.length, 1);
      expect(db.sales[sale.id]!.total, closeTo(12.9, 1e-9));
      expect(db.stock, {'a': 3, 'b': 5});
      expect(c.read(resaleDraftProvider), isNull);

      // The next sale is a normal new receipt.
      final next = await c
          .read(salesProvider.notifier)
          .completeSale(lines: [_lines.last]);
      expect(next.id, isNot(sale.id));
      expect(db.sales.length, 2);
    },
  );

  test('Undoing a receipt that is already gone changes nothing', () async {
    final db = _Db();
    final c = _container(db);
    final sale = await _sold(c);
    await c.read(salesProvider.notifier).voidSale('missing');
    expect(db.sales.keys, [sale.id]);
    expect(db.stock, {'a': 2, 'b': 4});
  });

  test('Items survive an app kill and refill the cart', () async {
    final db = _Db();
    final c = _container(db);
    final sale = await _sold(c, customer: _alice);
    await startResale(c.read, sale, guestName: 'Guest');
    c.read(cartProvider.notifier).setQty('a', 3);
    c.read(resaleDraftProvider.notifier).updateLines(c.read(cartProvider));
    await Future<void>.delayed(Duration.zero);

    // "Restart": fresh providers, same saved prefs.
    final c2 = _container(db);
    final drafts = c2.read(resaleDraftProvider.notifier);
    await drafts.loaded;
    final draft = c2.read(resaleDraftProvider);
    expect(draft?.saleId, sale.id);
    await restoreResaleIntoCart(c2.read, draft!, guestName: 'Guest');
    expect(c2.read(cartProvider).first.quantity, 3);
    expect(c2.read(cartProvider).length, 2);
    expect(c2.read(sellCustomerProvider)?.id, 'c1');
  });

  group('Cancel never removes items', () {
    Future<(ProviderContainer, GoRouter)> openSell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final db = _Db();
      final c = _container(db);
      late Sale sale;
      await tester.runAsync(() async {
        sale = await _sold(c, customer: _alice);
        await startResale(c.read, sale, guestName: 'Guest');
      });
      final router = GoRouter(
        initialLocation: '/sold',
        routes: [
          GoRoute(
            path: '/sold',
            builder: (_, _) => const Scaffold(body: Text('items sold')),
          ),
          GoRoute(path: '/sell', builder: (_, _) => const SellPage()),
          GoRoute(
            path: '/sell/add',
            builder: (_, _) => const SellAddProductsPage(),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      router.push('/sell');
      await tester.pumpAndSettle();
      expect(find.byType(SellPage), findsOneWidget);
      expect(find.textContaining('Editing receipt'), findsOneWidget);
      return (c, router);
    }

    testWidgets('Sell X keeps items + customer', (tester) async {
      final (c, _) = await openSell(tester);
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('items sold'), findsOneWidget);
      expect(c.read(cartProvider), _lines);
      expect(c.read(sellCustomerProvider)?.id, 'c1');
      expect(c.read(resaleDraftProvider), isNotNull);
    });

    testWidgets('System Back keeps items', (tester) async {
      final (c, _) = await openSell(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('items sold'), findsOneWidget);
      expect(c.read(cartProvider), _lines);
    });

    testWidgets('Add Items X restores the cart', (tester) async {
      final (c, router) = await openSell(tester);
      router.push('/sell/add');
      await tester.pumpAndSettle();
      c.read(cartProvider.notifier).removeItem('a');
      c.read(cartProvider.notifier).removeItem('b');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
      expect(find.byType(SellPage), findsOneWidget);
      expect(c.read(cartProvider), _lines);
    });
  });
}
