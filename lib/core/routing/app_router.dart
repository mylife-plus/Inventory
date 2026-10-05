import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/features/customers/presentation/customers_page.dart';
import 'package:inventory_app/features/inventory/presentation/inventory_page.dart';
import 'package:inventory_app/features/inventory/presentation/item_editor_page.dart';
import 'package:inventory_app/features/inventory/presentation/qr_label_page.dart';
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

  ref.listen(shopSettingsProvider, (_, __) => bump(), fireImmediately: true);
  ref.listen(appPrefsProvider, (_, __) => bump(), fireImmediately: true);
  ref.onDispose(gate.dispose);

  return GoRouter(
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

      final prefsDone =
          prefsAsync.valueOrNull?.prefsSetupDone ?? false;

      // Prefs (language / currency) — once only.
      if (!prefsDone && loc != '/setup') return '/setup';
      if (prefsDone && loc == '/setup') return '/inventory';

      // Old full onboarding unused — receipt details on first receipt.
      if (atOnboarding) return '/inventory';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashPage(),
      ),
      GoRoute(
        path: '/setup',
        builder: (_, __) => const PrefsSetupPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inventory',
                builder: (_, __) => const InventoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/customers',
                builder: (_, __) => const CustomersPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/turnover',
                builder: (_, __) => const TurnoverPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/inventory/item',
        builder: (_, __) => const ItemEditorPage(),
      ),
      GoRoute(
        path: '/inventory/item/:id',
        builder: (_, state) =>
            ItemEditorPage(itemId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/inventory/qr/:id',
        builder: (_, state) =>
            QrLabelPage(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sell',
        builder: (_, __) => const SellPage(),
      ),
      GoRoute(
        path: '/sell/add',
        builder: (_, __) => const SellAddProductsPage(),
      ),
      GoRoute(
        path: '/sell/scan',
        builder: (_, __) => const SellScannerPage(),
      ),
      GoRoute(
        path: '/sell/customer',
        builder: (_, state) => SelectCustomerPage(
          checkout: state.uri.queryParameters['checkout'] == '1',
          saleId: state.uri.queryParameters['saleId'],
        ),
      ),
      GoRoute(
        path: '/sell/receipt/:id',
        builder: (_, state) =>
            ReceiptPage(saleId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/customers/new',
        builder: (_, __) => const CustomerEditorPage(),
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
      GoRoute(
        path: '/receipts',
        builder: (_, __) => const ReceiptsYearsPage(),
      ),
      GoRoute(
        path: '/receipts/year/:year',
        builder: (_, state) => ReceiptsYearPage(
          year: int.tryParse(state.pathParameters['year'] ?? '') ??
              DateTime.now().year,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsPage(),
      ),
      GoRoute(
        path: '/settings/receipt',
        builder: (_, __) => const ReceiptDetailsSettingsPage(),
      ),
    ],
  );
});
