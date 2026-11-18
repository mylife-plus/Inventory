import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/turnover/presentation/turnover_page.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';

void main() {
  final rows = <TurnoverRowKey>[
    (title: 'banana', revenueCents: 500, lastSaleAt: DateTime(2026, 11, 3)),
    (title: 'Apple', revenueCents: 100, lastSaleAt: DateTime(2026, 11, 9)),
    (title: 'Cheese', revenueCents: 900, lastSaleAt: DateTime(2026, 11, 1)),
  ];
  List<String> order(SortState<TurnoverSortKey> s) =>
      ([...rows]..sort((a, b) => compareTurnoverRows(s, a, b)))
          .map((r) => r.title)
          .toList();

  test('Cashflow sort: A–Z (case-insensitive) and Z–A', () {
    expect(order(const SortState(TurnoverSortKey.name)),
        ['Apple', 'banana', 'Cheese']);
    expect(order(const SortState(TurnoverSortKey.name, reversed: true)),
        ['Cheese', 'banana', 'Apple']);
  });

  test('existing amount / recent orders unchanged', () {
    expect(order(const SortState(TurnoverSortKey.amount)),
        ['Cheese', 'banana', 'Apple']);
    expect(order(const SortState(TurnoverSortKey.amount, reversed: true)),
        ['Apple', 'banana', 'Cheese']);
    expect(order(const SortState(TurnoverSortKey.recent)),
        ['Apple', 'banana', 'Cheese']);
    expect(order(const SortState(TurnoverSortKey.recent, reversed: true)),
        ['Cheese', 'banana', 'Apple']);
  });
}
