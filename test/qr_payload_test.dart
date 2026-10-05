import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/qr/qr_payload.dart';

void main() {
  const id = '3f2b8c1e-9a4d-4e6f-8b2a-1c3d5e7f9a0b';
  final json = QrPayload.encodeItem(id: id, title: 'Cheese', price: 2.5);

  test('label without link encodes JSON and scans back to the item', () {
    final data = QrPayload.labelData(itemId: id, payload: json);
    final parsed = QrPayload.parse(data);
    expect(parsed.kind, QrKind.item);
    expect(parsed.id, id);
  });

  test('label with link keeps the link and still carries the item id', () {
    final data =
        QrPayload.labelData(itemId: id, payload: json, link: 'shop.com/cheese');
    expect(data, 'https://shop.com/cheese#inv=$id');
    final parsed = QrPayload.parse(data);
    expect(parsed.kind, QrKind.item);
    expect(parsed.id, id);
  });

  test('link that already has a fragment', () {
    final data = QrPayload.labelData(
      itemId: id,
      payload: json,
      link: 'https://shop.com/p#top',
    );
    expect(data, 'https://shop.com/p#top&inv=$id');
    expect(QrPayload.parse(data).id, id);
  });

  test('linkKey matches old link-only labels', () {
    expect(
      QrPayload.linkKey('https://www.Shop.com/cheese/'),
      QrPayload.linkKey('shop.com/cheese'),
    );
  });
}
