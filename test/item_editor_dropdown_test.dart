import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
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
import 'package:inventory_app/features/inventory/presentation/item_editor_page.dart';

/// Nov 14 client review: Add item, number keyboard open on Price/Amount,
/// tapping the Category dropdown must open its list (not just close the
/// keyboard and the list with it).
final _now = DateTime(2026, 11, 14);
final _items = [
  InventoryItem(
    id: 'a',
    title: 'Bread',
    price: 2.5,
    amount: 10,
    categoryName: 'Bakery',
    createdAt: _now,
    updatedAt: _now,
  ),
  InventoryItem(
    id: 'b',
    title: 'Cola',
    price: 1.5,
    amount: 10,
    categoryName: 'Drinks',
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

Future<void> _open(WidgetTester tester) async {
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
  final router = GoRouter(
    initialLocation: '/item',
    routes: [
      GoRoute(path: '/item', builder: (_, _) => const ItemEditorPage()),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: router,
        // Same app-wide "tap outside closes the keyboard" as lib/app.dart.
        builder: (context, child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('number keyboard open → tap Category: list opens and stays '
        '(${platform.name})', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _open(tester);
        await tester.tap(_field('Amount').first);
        await tester.pump();
        // Number keyboard up.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
        await tester.pumpAndSettle();
        expect(find.text('Bakery'), findsNothing);

        await tester.tap(_field('Category'));
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus?.context;
        expect(
          focused?.findAncestorWidgetOfExactType<TextField>()?.decoration
              ?.labelText,
          'Category',
          reason: 'focus moved to Category',
        );
        expect(find.text('Bakery'), findsOneWidget, reason: 'list is open');
        expect(find.text('Drinks'), findsOneWidget);

        // Text keyboard replaces the number one; the list must survive it.
        tester.view.viewInsets = const FakeViewPadding(bottom: 0);
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320 * 3);
        await tester.pumpAndSettle();
        expect(find.text('Bakery'), findsOneWidget, reason: 'list stays open');

        await tester.tap(find.text('Drinks'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(_field('Category')).controller?.text,
          'Drinks',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
