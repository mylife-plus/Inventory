import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/utils/formatters.dart';

/// Client: "5 x Cheese", never "5.0 x Cheese"; real fractions stay.
void main() {
  test('whole quantities have no decimals', () {
    expect(formatQty(5.0), '5');
    expect(formatQty(5), '5');
    expect(formatQty(0.0), '0');
    expect(formatQty(120.0), '120');
  });

  test('fractional quantities keep trimmed decimals', () {
    expect(formatQty(2.5), '2.5');
    expect(formatQty(0.25), '0.25');
    expect(formatQty(1.10), '1.1');
    expect(formatQty(2.999), '3');
  });
}
