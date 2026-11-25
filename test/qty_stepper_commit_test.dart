import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';

/// Sell edit sheet: typing a new qty then tapping Check must commit the field
/// even while it still has focus (otherwise the old cart qty is kept).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('QtyStepper.commitEdit applies typed value while focused',
      (tester) async {
    final key = GlobalKey<QtyStepperState>();
    var value = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: QtyStepper(
            key: key,
            value: value,
            max: 20,
            onChanged: (q) => value = q,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '0.4');
    await tester.pump();

    // Still focused — no blur commit yet; Check must force-commit.
    expect(value, 1.0);
    expect(key.currentState!.commitEdit(), 0.4);
    expect(value, 0.4);
  });
}
