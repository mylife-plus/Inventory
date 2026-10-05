import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/app.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: InventoryApp()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(InventoryApp), findsOneWidget);
  });
}
