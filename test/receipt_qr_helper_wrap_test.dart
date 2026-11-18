import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/settings/presentation/settings_page.dart';

/// Nov 14 client review: Receipt Details → the text under "QR-Label" was
/// cut off with "…". It must wrap in full in every language.
class _Repo extends ShopRepository {
  _Repo() : super(AppDatabase.instance);
  @override
  Future<ShopSettings> get() async =>
      const ShopSettings(companyName: 'Demo Shop', city: 'Berlin');
  @override
  Future<void> save(ShopSettings settings) async {}
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final lang in ['en', 'de', 'es', 'fr', 'pt']) {
    testWidgets('QR-Label helper wraps fully at 360 px ($lang)', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final t = S(lang);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tProvider.overrideWithValue(t),
            shopRepositoryProvider.overrideWithValue(_Repo()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ReceiptDetailsSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final helper = find.text(t('receipt_qr_link_helper'));
      await tester.scrollUntilVisible(helper, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(helper, findsOneWidget);
      final para = tester.renderObject<RenderParagraph>(helper);
      expect(para.didExceedMaxLines, isFalse, reason: 'no "…" in $lang');
      expect(para.size.height, greaterThan(20), reason: 'wraps to 2+ lines');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
