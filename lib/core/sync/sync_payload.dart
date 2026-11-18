import 'dart:convert';
import 'dart:typed_data';

import 'package:inventory_app/core/sync/sync_crypto.dart';

/// What a device shows in its pairing QR: identity + public key only.
class PairingPayload {
  const PairingPayload({
    required this.deviceId,
    required this.publicKey,
    required this.nonce,
    this.appName = 'Inventory',
  });

  static const prefix = 'INVSYNC1:';

  final String deviceId;
  final Uint8List publicKey;
  final String nonce;
  final String appName;

  String encode() =>
      prefix +
      b64url(utf8.encode(jsonEncode({
        'd': deviceId,
        'k': b64(publicKey),
        'n': nonce,
        'a': appName,
      })));

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{16,64}$');
  static final _nonceRe = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  /// `null` when [raw] is not a valid Inventory device-sync code.
  static PairingPayload? tryParse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (!s.startsWith(prefix) || s.length > 600) return null;
    try {
      var body = s.substring(prefix.length);
      body = body.padRight((body.length + 3) ~/ 4 * 4, '=');
      final m = jsonDecode(utf8.decode(base64Url.decode(body)));
      if (m is! Map) return null;
      final id = m['d'], k = m['k'], n = m['n'], a = m['a'];
      if (id is! String || !_idRe.hasMatch(id)) return null;
      if (n is! String || !_nonceRe.hasMatch(n)) return null;
      if (k is! String) return null;
      final key = base64Decode(k);
      if (key.length != 32) return null;
      return PairingPayload(
        deviceId: id,
        publicKey: key,
        nonce: n,
        appName: a is String && a.length <= 40 ? a : 'Inventory',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Admin device's one-time invite QR (v2 groups): the group, the admin's
/// public keys (so the newcomer can verify what the admin sends back) and
/// a single-use secret the relay checks once.
class GroupInvitePayload {
  const GroupInvitePayload({
    required this.groupId,
    required this.adminId,
    required this.adminKey,
    required this.adminSignKey,
    required this.secret,
  });

  static const prefix = 'INVSYNC2:';

  final String groupId;
  final String adminId;
  final Uint8List adminKey; // X25519
  final Uint8List adminSignKey; // Ed25519
  final String secret;

  String encode() =>
      prefix +
      b64url(utf8.encode(jsonEncode({
        'g': groupId,
        'd': adminId,
        'x': b64(adminKey),
        's': b64(adminSignKey),
        'k': secret,
      })));

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

  static GroupInvitePayload? tryParse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (!s.startsWith(prefix) || s.length > 700) return null;
    try {
      var body = s.substring(prefix.length);
      body = body.padRight((body.length + 3) ~/ 4 * 4, '=');
      final m = jsonDecode(utf8.decode(base64Url.decode(body)));
      if (m is! Map) return null;
      final g = m['g'], d = m['d'], x = m['x'], sk = m['s'], k = m['k'];
      if (g is! String || !_idRe.hasMatch(g)) return null;
      if (d is! String || !_idRe.hasMatch(d)) return null;
      if (k is! String || !_idRe.hasMatch(k)) return null;
      if (x is! String || sk is! String) return null;
      final xk = base64Decode(x), sg = base64Decode(sk);
      if (xk.length != 32 || sg.length != 32) return null;
      return GroupInvitePayload(
        groupId: g,
        adminId: d,
        adminKey: xk,
        adminSignKey: sg,
        secret: k,
      );
    } catch (_) {
      return null;
    }
  }
}
