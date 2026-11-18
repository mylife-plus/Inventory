import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/shared/widgets/scroll_chrome.dart';

/// The list must reserve exactly the measured header height, even when the
/// page never rebuilds after the first frame (data already cached).
void main() {
  Widget page({double headerH = 130}) => MaterialApp(
        home: ScrollChromeHost(
          builder: (context, chrome) => CustomScrollView(
            controller: chrome.scrollController,
            physics: kScrollChromePhysics,
            slivers: [
              ...ScrollChrome.headerSlivers(
                context: context,
                chrome: chrome,
                header: (_) => SizedBox(height: headerH, child: const Text('H')),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(
                  key: Key('first_card'),
                  height: 80,
                  child: Text('Total'),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 3000)),
            ],
          ),
        ),
      );

  testWidgets('first card starts below the header without a page rebuild',
      (tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.byKey(const Key('first_card'))).dy;
    // status bar inset is 0 in tests → header occupies 0..130.
    expect(top, 130);
  });

  testWidgets('spacer does not rebuild the header on every scroll frame',
      (tester) async {
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: ScrollChromeHost(
        builder: (context, chrome) => CustomScrollView(
          controller: chrome.scrollController,
          slivers: [
            ...ScrollChrome.headerSlivers(
              context: context,
              chrome: chrome,
              header: (_) {
                builds++;
                return const SizedBox(height: 130);
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 3000)),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final before = builds;
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -10));
      await tester.pump();
    }
    // Only the overlay copy may follow the scroll; the hidden measuring copy
    // in the list must not rebuild per frame.
    expect(builds - before, lessThanOrEqualTo(12));
  });
}
