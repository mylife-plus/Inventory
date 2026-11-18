import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/routing/app_router.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/settings/presentation/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nov 12 client review: Receipt Details → ✓ must save and close.
/// Uses the app's real router: saving updates shop settings, which used to
/// refresh the router right as the page popped and keep it open.
class _Repo extends ShopRepository {
  _Repo(this.value) : super(AppDatabase.instance);
  ShopSettings value;
  int saves = 0;
  @override
  Future<ShopSettings> get() async => value;
  @override
  Future<void> save(ShopSettings settings) async {
    saves++;
    value = settings;
  }
}

class _Sales extends SalesNotifier {
  @override
  Future<List<Sale>> build() async => const [];
}

Future<(_Repo, ProviderContainer)> _open(
  WidgetTester tester, {
  String company = 'Demo Shop',
}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'locale': 'en',
    'prefs_setup_done': true,
  });
  final repo = _Repo(ShopSettings(companyName: company, city: 'Berlin'));
  final container = ProviderContainer(
    overrides: [
      tProvider.overrideWithValue(S('en')),
      shopRepositoryProvider.overrideWithValue(repo),
      salesProvider.overrideWith(_Sales.new),
    ],
  );
  addTearDown(container.dispose);
  await container.read(shopSettingsProvider.future);
  await container.read(appPrefsProvider.future);
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  router.go('/receipts');
  await tester.pumpAndSettle();
  router.push('/settings/receipt');
  await tester.pumpAndSettle();
  expect(find.byType(ReceiptDetailsSettingsPage), findsOneWidget);
  return (repo, container);
}

/// Unmount and let the splash safety timer (5 s) run out.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

Finder get _check => find.byIcon(Icons.check_rounded);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('✓ saves and closes on the first tap', (tester) async {
    final (repo, _) = await _open(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Berlin'),
      'Hamburg',
    );
    await tester.pump();
    await tester.tap(_check);
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.value.city, 'Hamburg');
    expect(find.byType(ReceiptDetailsSettingsPage), findsNothing);
    await _close(tester);
  });

  testWidgets('empty company: stays open and shows the error', (tester) async {
    final (repo, _) = await _open(tester, company: '');
    await tester.tap(_check);
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(find.byType(ReceiptDetailsSettingsPage), findsOneWidget);
    expect(find.text(S('en')('required')), findsOneWidget);
    await _close(tester);
  });
}
