import 'dart:convert';

/// Encodes / parses QR payloads used on product labels & receipts.
/// Compatible with Tocca-style URLs (`https://tocca.io/i/{id}`) plus rich JSON.
class QrPayload {
  QrPayload._();

  static const itemHostPath = 'https://tocca.io/i/';
  static const receiptHostPath = 'https://tocca.io/r/';

  /// Compact JSON with full item fields — reliable offline scans.
  static String encodeItem({
    required String id,
    required String title,
    required double price,
    String? unit,
  }) {
    return jsonEncode({
      'v': 1,
      'type': 'item',
      'id': id,
      'title': title,
      'price': price,
      if (unit != null && unit.isNotEmpty) 'unit': unit,
    });
  }

  static String encodeItemUrl(String id) => '$itemHostPath$id';

  static String encodeReceipt(String saleId) => '$receiptHostPath$saleId';

  /// Normalize inventory / UUID ids from noisy scanner output.
  static String? normalizeId(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    try {
      s = Uri.decodeComponent(s);
    } catch (_) {
      // keep raw
    }
    s = s.trim();
    if (s.startsWith('{') && s.endsWith('}') && s.length > 2) {
      s = s.substring(1, s.length - 1).trim();
    }
    // Strip surrounding quotes from JSON-ish fragments.
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return null;
    // UUIDs / hex ids are case-insensitive in practice.
    if (RegExp(r'^[0-9a-fA-F-]{8,}$').hasMatch(s)) {
      return s.toLowerCase();
    }
    return s;
  }

  static ParsedQr parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const ParsedQr.unknown('');

    // JSON rich payload (allow leading BOM / whitespace already trimmed)
    final jsonStart = text.indexOf('{');
    if (jsonStart >= 0) {
      final jsonText = text.substring(jsonStart);
      try {
        final map = jsonDecode(jsonText) as Map<String, dynamic>;
        final type = (map['type'] ?? map['t'] ?? '').toString();
        final id = normalizeId((map['id'] ?? map['itemId'] ?? map['uuid'] ?? '')
            .toString());
        if (id == null || id.isEmpty) {
          // fall through to other formats
        } else if (type == 'item' || type == 'i' || type.isEmpty) {
          return ParsedQr.item(
            id: id,
            title: map['title']?.toString() ?? map['n']?.toString(),
            price: (map['price'] ?? map['p']) is num
                ? (map['price'] ?? map['p']).toDouble()
                : double.tryParse('${map['price'] ?? map['p'] ?? ''}'),
            unit: map['unit']?.toString() ?? map['u']?.toString(),
            raw: text,
          );
        } else if (type == 'receipt' || type == 'r') {
          return ParsedQr.receipt(id: id, raw: text);
        }
      } catch (_) {
        // fall through
      }
    }

    // inv:{id}
    if (text.toLowerCase().startsWith('inv:')) {
      final id = normalizeId(text.substring(4));
      if (id != null) return ParsedQr.item(id: id, raw: text);
    }

    // item:{id} / product:{id}
    final lower = text.toLowerCase();
    for (final prefix in ['item:', 'product:', 'p:']) {
      if (lower.startsWith(prefix)) {
        final id = normalizeId(text.substring(prefix.length));
        if (id != null) return ParsedQr.item(id: id, raw: text);
      }
    }

    // Tocca / URL style
    final uri = Uri.tryParse(text);
    if (uri != null &&
        (uri.hasScheme || text.contains('/')) &&
        uri.pathSegments.isNotEmpty) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        final last = normalizeId(segs.last);
        final kind =
            segs.length >= 2 ? segs[segs.length - 2].toLowerCase() : '';
        if (last != null) {
          if (kind == 'i' ||
              kind == 'item' ||
              kind == 'p' ||
              kind == 'product') {
            return ParsedQr.item(id: last, raw: text);
          }
          if (kind == 'r' || kind == 'receipt') {
            return ParsedQr.receipt(id: last, raw: text);
          }
          if (kind == 'c' || kind == 'customer') {
            return ParsedQr.customer(id: last, raw: text);
          }
          // bare id at end of tocca.io URL
          if (uri.host.toLowerCase().contains('tocca')) {
            return ParsedQr.item(id: last, raw: text);
          }
        }
      }
      // Query ?id= / ?itemId=
      final qId = normalizeId(
        uri.queryParameters['id'] ??
            uri.queryParameters['itemId'] ??
            uri.queryParameters['item'],
      );
      if (qId != null) {
        return ParsedQr.item(id: qId, raw: text);
      }
    }

    // Plain UUID / id
    final plain = normalizeId(text);
    if (plain != null && RegExp(r'^[0-9a-fA-F-]{8,}$').hasMatch(plain)) {
      return ParsedQr.item(id: plain, raw: text);
    }

    return ParsedQr.unknown(text);
  }
}

enum QrKind { item, receipt, customer, unknown }

class ParsedQr {
  const ParsedQr._({
    required this.kind,
    required this.raw,
    this.id,
    this.title,
    this.price,
    this.unit,
  });

  const ParsedQr.item({
    required String id,
    String? title,
    double? price,
    String? unit,
    required String raw,
  }) : this._(
          kind: QrKind.item,
          id: id,
          title: title,
          price: price,
          unit: unit,
          raw: raw,
        );

  const ParsedQr.receipt({required String id, required String raw})
      : this._(kind: QrKind.receipt, id: id, raw: raw);

  const ParsedQr.customer({required String id, required String raw})
      : this._(kind: QrKind.customer, id: id, raw: raw);

  const ParsedQr.unknown(String raw)
      : this._(kind: QrKind.unknown, raw: raw);

  final QrKind kind;
  final String raw;
  final String? id;
  final String? title;
  final double? price;
  final String? unit;
}
