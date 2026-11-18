import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/turnover/turnover_money.dart';

void main() {
  group('cent-safe sums', () {
    test('line totals that used to drift by 0.01', () {
      // Classic float: 14.0 * 0.1 * many lines — use cents instead.
      final lines = <({double price, double qty})>[
        (price: 18.9, qty: 7.5),
        (price: 14.0, qty: 10.5),
        (price: 2.5, qty: 3),
      ];
      var cents = 0;
      var naive = 0.0;
      for (final l in lines) {
        cents += lineTotalCents(unitPrice: l.price, quantity: l.qty);
        naive += l.price * l.qty;
      }
      expect(centsToMoney(cents), closeTo((naive * 100).round() / 100.0, 1e-9));
      // Year vs month style: sum of rounded lines == total cents.
      expect(cents, 14175 + 14700 + 750);
    });

    test('moneyToCents uses (amount*100).round()', () {
      expect(moneyToCents(1.00), 100);
      expect(moneyToCents(1.239), 124);
      expect(moneyToCents(73.504516129), 7350);
    });
  });
}
