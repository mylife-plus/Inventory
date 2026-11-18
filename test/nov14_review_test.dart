import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:inventory_app/features/shell/presentation/main_shell.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';

/// Nov 14 client review: tab swipe order, blue arrow on collapsed
/// sections, Sell → Add items floating ✕/✓ that hide on scroll, and the
/// keyboard-dismiss tap on a category not collapsing it.
///
/// Screenshots: `REVIEW_SHOTS_DIR=/some/dir flutter test <this file>`.
final _shotsDir = Platform.environment['REVIEW_SHOTS_DIR'];
final _boundary = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotsDir == null) return;
  await tester.runAsync(() async {
    final ro = _boundary.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final ui.Image img = await ro.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('$_shotsDir/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

final _now = DateTime(2026, 11, 14);
final _items = [
  for (var i = 1; i <= 24; i++)
    InventoryItem(
      id: 'i$i',
      title: 'Item $i',
      price: 2.5,
      amount: 10,
      categoryName: i <= 12 ? 'Bakery' : 'Drinks',
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

Future<void> _openSellAdd(WidgetTester tester) async {
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
    SaleLine(itemId: 'i1', title: 'Item 1', unitPrice: 2.5, quantity: 1),
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
    RepaintBoundary(
      key: _boundary,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    ),
  );
  router.push('/sell/add');
  await tester.pumpAndSettle();
}

/// 1 = fully shown, 0 = hidden (AnimatedOpacity around the ✕/✓).
double _barOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find
        .ancestor(
          of: find.byType(ConfirmCancelBar),
          matching: find.byType(AnimatedOpacity),
        )
        .first)
    .opacity;

bool _textFocused() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null &&
      (ctx.widget is EditableText ||
          ctx.findAncestorWidgetOfExactType<EditableText>() != null);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('top menu swipe', () {
    // ClientHeader: [previous, next, CURRENT] = [(i+2)%3, (i+1)%3, i].
    const names = ['Inventory', 'Customers', 'Cashflow'];
    test('left→right opens the icon next to the title, right→left the outer '
        'one; every tab, both ways', () {
      for (var i = 0; i < 3; i++) {
        final header = [(i + 2) % 3, (i + 1) % 3];
        expect(MainShell.swipeTarget(i, 600), header[1],
            reason: '${names[i]} left→right');
        expect(MainShell.swipeTarget(i, -600), header[0],
            reason: '${names[i]} right→left');
        // Swiping back returns to where we started.
        expect(MainShell.swipeTarget(MainShell.swipeTarget(i, 600)!, -600), i);
      }
      // The client's case: Customers (📦 💸 👤) left→right → Cashflow.
      expect(names[MainShell.swipeTarget(1, 600)!], 'Cashflow');
      expect(MainShell.swipeTarget(1, 100), isNull, reason: 'slow drag');
    });
  });

  testWidgets('collapsed section: blue arrow; open: grey as before',
      (tester) async {
    var open = true;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return SectionHeader(
            title: 'Bakery',
            expanded: open,
            onToggle: () => s(() => open = !open),
          );
        }),
      ),
    ));
    Color arrow() => tester
        .widget<Icon>(find.byIcon(Icons.arrow_drop_down_rounded))
        .color!;
    expect(arrow(), AppPalette.dark.textMuted);
    await tester.tap(find.text('Bakery'));
    await tester.pumpAndSettle();
    expect(open, isFalse);
    expect(arrow(), AppPalette.dark.fabBorder);
    set(() => open = true);
    await tester.pumpAndSettle();
    expect(arrow(), AppPalette.dark.textMuted);
  });

  testWidgets('Sell → Add items: ✕/✓ float without a bar and hide on scroll '
      'down, back on scroll up', (tester) async {
    await _openSellAdd(tester);
    final scaffold = tester.widget<Scaffold>(find
        .ancestor(
          of: find.byType(ConfirmCancelBar),
          matching: find.byType(Scaffold),
        )
        .first);
    expect(scaffold.bottomNavigationBar, isNull, reason: 'no bar behind them');
    expect(_barOpacity(tester), 1);
    await _shot(tester, 'sell_add_1_top');

    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 0, reason: 'scrolling down hides them');
    await _shot(tester, 'sell_add_2_scrolled_down_hidden');

    await tester.drag(list, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 1, reason: 'scrolling up shows them');
    await _shot(tester, 'sell_add_3_scrolled_up_shown');

    // The last card can scroll clear of the buttons.
    await tester.drag(list, const Offset(0, -5000));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 60));
    await tester.pumpAndSettle();
    final lastCard = tester.getRect(find.text('Item 24'));
    final check = tester.getRect(find.byIcon(Icons.check_rounded));
    expect(lastCard.bottom, lessThan(check.top), reason: 'not covered');
    await _shot(tester, 'sell_add_4_end_of_list');
  });

  testWidgets('Sell → Add items: quantity keyboard open, tap on a category '
      'only closes the keyboard; the category stays open', (tester) async {
    await _openSellAdd(tester);
    final qty = find.descendant(
      of: find.byKey(const ValueKey('qty-i1')),
      matching: find.byType(TextField),
    );
    await tester.tap(qty);
    await tester.pump();
    expect(_textFocused(), isTrue);
    expect(find.text('Item 2'), findsOneWidget);

    await tester.tap(find.text('Bakery'));
    await tester.pumpAndSettle();
    expect(_textFocused(), isFalse, reason: 'keyboard closed');
    expect(find.text('Item 2'), findsOneWidget, reason: 'Bakery still open');

    // Keyboard gone: the next tap collapses as before.
    await tester.tap(find.text('Bakery'));
    await tester.pumpAndSettle();
    expect(find.text('Item 2'), findsNothing);
  });

  testWidgets('Sell → Add items: ✕/✓ stay away while the keyboard is open',
      (tester) async {
    await _openSellAdd(tester);
    expect(_barOpacity(tester), 1);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 0, reason: 'not floating above the keyboard');
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 1);
  });
}
