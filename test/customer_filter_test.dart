import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/features/customers/presentation/customer_list_tools.dart';
import 'package:inventory_app/domain/models/models.dart';

Customer _c(String id, {String? phone, List<CustomerCustomField> f = const []}) =>
    Customer(
      id: id,
      name: id,
      phone: phone,
      customFields: f,
      createdAt: DateTime(2026),
    );

void main() {
  final a = _c('a', phone: '1', f: const [
    CustomerCustomField(label: 'Signal', value: '+49 1'),
    CustomerCustomField(label: 'Empty', value: ' '),
  ]);
  final b = _c('b', f: const [CustomerCustomField(label: 'signal', value: '')]);

  test('custom field labels are collected once, A–Z', () {
    expect(customFieldLabels([a, b]), ['Empty', 'Signal']);
  });

  test('filter by custom field needs a filled value', () {
    const f = CustomerFilter(customFields: {'signal'});
    expect(f.isActive, isTrue);
    expect(f.matches(a, null), isTrue);
    expect(f.matches(b, null), isFalse);
    expect(const CustomerFilter(customFields: {'empty'}).matches(a, null),
        isFalse);
  });

  test('built-in and custom options combine', () {
    const f = CustomerFilter(
      contacts: {ContactKind.phone},
      customFields: {'signal'},
    );
    expect(f.matches(a, null), isTrue);
    expect(f.matches(_c('c', phone: '2'), null), isFalse);
  });
}
