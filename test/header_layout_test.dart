import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';

/// Oct 10 client review: sub-page titles are centered; the main tab pages
/// (Inventory, Customers, Turnover) and the main Sell page stay left-aligned.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final dark in [true, false]) {
    testWidgets('sub-page app bar title is centered '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text('Edit Item'),
            ),
          ),
        ),
      );
      final title = tester.getRect(find.text('Edit Item'));
      expect(title.center.dx, closeTo(412 / 2, 1.5));
    });
  }

  testWidgets('tab header title is left-aligned next to the nav buttons',
      (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tProvider.overrideWithValue(S('en'))],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Column(
              children: [
                ClientHeader(
                  section: 0,
                  title: 'Inventory',
                  titleAsset: AppAssets.inventory,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final title = tester.getRect(find.text('Inventory'));
    // 16 padding + 2×44 nav buttons + 10 between + 10 gap + 26 icon + 8.
    const expectedLeft = 16 + 44 + 10 + 44 + 10 + 26 + 8;
    expect(title.left, closeTo(expectedLeft, 1.5));
    // Clearly left of center on a phone.
    expect(title.center.dx, lessThan(412 / 2));
  });
}
