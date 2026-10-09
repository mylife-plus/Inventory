import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';

/// Oct 9 client review: every page title is centered — sub pages (with a
/// back button and actions) and the tab headers (Inventory, Customers,
/// Turnover) alike.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final dark in [true, false]) {
    testWidgets('app bar title is centered on screen '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final theme = dark ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text('Edit Item'),
              actions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.edit)),
              ],
            ),
          ),
        ),
      );
      final title = tester.getRect(find.text('Edit Item'));
      expect(title.center.dx, closeTo(412 / 2, 1.5));
    });
  }

  testWidgets('tab header title is centered on screen', (tester) async {
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
    // Icon (26) + gap (8) + title form one group centered on the screen.
    final groupLeft = title.left - 8 - 26;
    final groupCenter = (groupLeft + title.right) / 2;
    expect(groupCenter, closeTo(412 / 2, 2));
  });
}
