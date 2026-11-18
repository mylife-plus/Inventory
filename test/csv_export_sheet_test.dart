import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/date_bounds.dart';
import 'package:inventory_app/shared/widgets/date_range_fields.dart';

/// Nov 11: Receipts download / Export Turnover pop-up — From / To default
/// to all data, Export shows a loading wheel, then returns the CSV file.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('defaults to first → last day; wheel while exporting',
      (tester) async {
    final bounds = DateBounds(DateTime(2026, 9, 3), DateTime(2026, 11, 10));
    final gate = Completer<File>();
    DateTime? gotFrom, gotTo;
    File? result;
    var closed = false;

    await tester.pumpWidget(ProviderScope(
      overrides: [tProvider.overrideWithValue(S('en'))],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showCsvExportSheet(
                    context: ctx,
                    title: 'Export Receipts',
                    bounds: bounds,
                    build: (from, to) {
                      gotFrom = from;
                      gotTo = to;
                      return gate.future;
                    },
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('03.09.2026'), findsOneWidget);
    expect(find.text('10.11.2026'), findsOneWidget);
    expect(find.text(S('en')('export_range_all')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export_csv_button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('export_loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(gotFrom, bounds.first);
    expect(gotTo, bounds.last);

    final f = File('${Directory.systemTemp.path}/x.csv');
    gate.complete(f);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result?.path, f.path);
  });
}
