import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';

SaleLine _l(String id, double q) =>
    SaleLine(itemId: id, title: id, unitPrice: 1, quantity: q);

void main() {
  test('unchanged receipt edit never moves stock', () {
    final lines = [_l('a', 2), _l('b', 1.5)];
    expect(saleStockDeltas(lines, List.of(lines)), isEmpty);
    // Same totals in a different order / split across lines.
    expect(
      saleStockDeltas(lines, [_l('b', 1), _l('a', 2), _l('b', 0.5)]),
      isEmpty,
    );
  });

  test('net deltas: more sold deducts, fewer/removed restocks', () {
    final d = saleStockDeltas(
      [_l('a', 2), _l('b', 3)],
      [_l('a', 5), _l('c', 1)],
    );
    expect(d, {'a': 3, 'b': -3, 'c': 1});
  });
}
