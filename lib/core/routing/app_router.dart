import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/features/customers/presentation/customers_page.dart';
import 'package:inventory_app/features/inventory/presentation/inventory_page.dart';
import 'package:inventory_app/features/inventory/presentation/item_editor_page.dart';
import 'package:inventory_app/features/inventory/presentation/qr_label_page.dart';
import 'package:inventory_app/features/inventory/presentation/qr_print_preview_page.dart';
import 'package:inventory_app/features/onboarding/presentation/onboarding_page.dart';
import 'package:inventory_app/features/onboarding/presentation/prefs_setup_page.dart';
import 'package:inventory_app/features/receipts/presentation/receipt_page.dart';
import 'package:inventory_app/features/sell/presentation/sell_page.dart';
import 'package:inventory_app/features/settings/presentation/settings_page.dart';
import 'package:inventory_app/features/shell/presentation/main_shell.dart';
import 'package:inventory_app/features/splash/presentation/splash_page.dart';
import 'package:inventory_app/features/turnover/presentation/turnover_page.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final gate = ValueNotifier<int>(0);

  void bump() => gate.value++;

  ref.listen(shopSettingsProvider, (_, _) => bump(), fireImmediately: true);
  ref.listen(appPrefsProvider, (_, _) => bump(), fireImmediately: true);
  ref.onDispose(gate.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: gate,
    redirect: (context, state) {
      final settings = ref.read(shopSettingsProvider);
      final prefsAsync = ref.read(appPrefsProvider);
      final loc = state.matchedLocation;
      final atSplash = loc == '/splash';
      final atOnboarding = loc == '/onboarding';

      final settingsReady = settings.hasValue || settings.hasError;
      final prefsReady = prefsAsync.hasValue || prefsAsync.hasError;

      if (!settingsReady || !prefsReady) {
        return atSplash ? null : '/splash';
      }

      // Splash animates, then navigates itself.
      if (atSplash) return null;

      final prefsDone = prefsAsync.valueOrNull?.prefsSetupDone ?? false;

      // Prefs (language / currency) — once only.
      if (!prefsDone && loc != '/setup') return '/setup';
      if (prefsDone && loc == '/setup') return '/inventory';

      // Old full onboarding unused — receipt details on first receipt.
      if (atOnboarding) return '/inventory';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/setup', builder: (_, _) => const PrefsSetupPage()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inventory',
                builder: (_, _) => const InventoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/customers',
                builder: (_, _) => const CustomersPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/turnover',
                builder: (_, _) => const TurnoverPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/inventory/item',
        builder: (_, _) => const ItemEditorPage(),
      ),
      GoRoute(
        path: '/inventory/item/:id',
        builder: (_, state) =>
            ItemEditorPage(itemId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/inventory/qr/:id',
        builder: (_, state) => QrLabelPage(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/inventory/qr/:id/print',
        builder: (_, state) {
          final args = state.extra;
          // No args (e.g. restored deep link): back to the label editor.
          if (args is! QrPrintArgs) {
            return QrLabelPage(itemId: state.pathParameters['id']!);
          }
          return QrPrintPreviewPage(args: args);
        },
      ),
      GoRoute(path: '/sell', builder: (_, _) => const SellPage()),
      GoRoute(
        path: '/sell/add',
        builder: (_, _) => const SellAddProductsPage(),
      ),
      GoRoute(path: '/sell/scan', builder: (_, _) => const SellScannerPage()),
      GoRoute(
        path: '/sell/customer',
        builder: (_, state) => SelectCustomerPage(
          checkout: state.uri.queryParameters['checkout'] == '1',
          saleId: state.uri.queryParameters['saleId'],
        ),
      ),
      GoRoute(
        path: '/sell/receipt/:id',
        builder: (_, state) => ReceiptPage(saleId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/customers/new',
        builder: (_, _) => const CustomerEditorPage(),
      ),
      GoRoute(
        path: '/customers/edit/:id',
        builder: (_, state) =>
            CustomerEditorPage(customerId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (_, state) =>
            CustomerDetailPage(customerId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/receipts', builder: (_, _) => const ReceiptsYearsPage()),
      GoRoute(
        path: '/receipts/year/:year',
        builder: (_, state) => ReceiptsYearPage(
          year:
              int.tryParse(state.pathParameters['year'] ?? '') ??
              DateTime.now().year,
        ),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/settings/receipt',
        builder: (_, _) => const ReceiptDetailsSettingsPage(),
      ),
    ],
  );

  // Receipt Edit: leaving Sell without completing (any route) or an app
  // kill mid-edit restores the original receipt and stock.
  ref.onDispose(attachResaleGuard(router, ref.read));
  unawaited(restoreAbandonedResale(ref.read));
  return router;
});
