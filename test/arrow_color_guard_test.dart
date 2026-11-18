// Client, Nov 14 + 16: every dropdown / collapse arrow is accent blue
// (AppPalette.fabBorder) while its content is hidden. This scans lib/ so a
// new arrow that bypasses SectionHeader and forgets the blue fails here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _arrow = RegExp(
  r'Icons\.(arrow_drop_down|expand_more|expand_less|keyboard_arrow_down|'
  r'keyboard_arrow_up|arrow_drop_up|unfold_more)',
);

List<File> _dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('every dropdown / collapse arrow icon is coloured fabBorder', () {
    final misses = <String>[];
    var found = 0;
    for (final f in _dartFiles()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!_arrow.hasMatch(lines[i])) continue;
        found++;
        final from = (i - 6).clamp(0, lines.length);
        final to = (i + 5).clamp(0, lines.length);
        final window = lines.sublist(from, to).join('\n');
        if (!window.contains('fabBorder')) misses.add('${f.path}:${i + 1}');
      }
    }
    expect(found, greaterThan(5), reason: 'scan found no arrows at all');
    expect(misses, isEmpty, reason: 'arrows without the blue: $misses');
  });

  test('no hand-made collapsible arrows outside SectionHeader', () {
    final custom = RegExp(r'AnimatedRotation|RotationTransition|ExpansionTile|'
        r'ExpansionPanel|DropdownButtonFormField|DropdownMenu<');
    final misses = <String>[];
    for (final f in _dartFiles()) {
      if (f.path.endsWith('shared/widgets/app_widgets.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (custom.hasMatch(lines[i])) misses.add('${f.path}:${i + 1}');
      }
    }
    expect(misses, isEmpty,
        reason: 'use SectionHeader / AppDropdown (blue arrow): $misses');
  });

  test('collapsible year / month / category headers use SectionHeader', () {
    const pages = {
      'lib/features/turnover/presentation/turnover_page.dart': 2,
      'lib/features/receipts/presentation/receipt_page.dart': 2,
      'lib/features/customers/presentation/customers_page.dart': 2,
      'lib/features/inventory/presentation/inventory_page.dart': 1,
      'lib/features/sell/presentation/sell_page.dart': 1,
    };
    pages.forEach((path, n) {
      final src = File(path).readAsStringSync();
      final count = RegExp(r'SectionHeader\(\s*\n?\s*(key:[^\n]*\n\s*)?title:[^\n]*\n\s*(trailing:[^\n]*\n\s*)?expanded:')
          .allMatches(src)
          .length;
      expect(count, greaterThanOrEqualTo(n), reason: path);
    });
  });
}
