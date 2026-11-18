import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/customers/presentation/customer_list_tools.dart';
import 'package:inventory_app/features/inventory/presentation/item_list_tools.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';

Customer _c(String id, String name) => Customer(
      id: id,
      name: name,
      createdAt: DateTime(2024, 1, 1),
    );

InventoryItem _i(String id, String title, {double price = 0, double amount = 0}) =>
    InventoryItem(
      id: id,
      title: title,
      price: price,
      amount: amount,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

void main() {
  test('Highest Spend lists highest totalSpent first', () {
    final list = [_c('a', 'Ann'), _c('b', 'Bob'), _c('c', 'Cat')];
    final stats = {
      'a': const CustomerStats(purchaseCount: 1, totalSpent: 50),
      'b': const CustomerStats(purchaseCount: 1, totalSpent: 200),
      'c': const CustomerStats(purchaseCount: 1, totalSpent: 100),
    };
    final sorted = sortCustomers(
      list,
      const SortState(CustomerSortKey.spent),
      stats,
    );
    expect(sorted.map((e) => e.id).toList(), ['b', 'c', 'a']);
  });

  test('Lowest Spend (reversed) lists lowest first', () {
    final list = [_c('a', 'Ann'), _c('b', 'Bob'), _c('c', 'Cat')];
    final stats = {
      'a': const CustomerStats(purchaseCount: 1, totalSpent: 50),
      'b': const CustomerStats(purchaseCount: 1, totalSpent: 200),
      'c': const CustomerStats(purchaseCount: 1, totalSpent: 100),
    };
    final sorted = sortCustomers(
      list,
      const SortState(CustomerSortKey.spent, reversed: true),
      stats,
    );
    expect(sorted.map((e) => e.id).toList(), ['a', 'c', 'b']);
  });

  test('Name A–Z default', () {
    final list = [_c('b', 'Bob'), _c('a', 'Ann'), _c('c', 'Cat')];
    final sorted = sortCustomers(
      list,
      const SortState(CustomerSortKey.name),
      const {},
    );
    expect(sorted.map((e) => e.name).toList(), ['Ann', 'Bob', 'Cat']);
  });

  test('Highest Price lists highest first', () {
    final list = [
      _i('a', 'A', price: 10),
      _i('b', 'B', price: 30),
      _i('c', 'C', price: 20),
    ];
    final sorted = sortItems(list, const SortState(ItemSortKey.price));
    expect(sorted.map((e) => e.id).toList(), ['b', 'c', 'a']);
  });
}
