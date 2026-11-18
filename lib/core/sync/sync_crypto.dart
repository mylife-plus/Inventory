import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Random bytes from a CSPRNG.
Uint8List syncRandomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

String b64(List<int> bytes) => base64Encode(bytes);
Uint8List unb64(String s) => base64Decode(s);
String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List sha256Bytes(List<int> data) =>
    Uint8List.fromList(const DartSha256().hashSync(data).bytes);

String sha256Hex(List<int> data) => sha256Bytes(data)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// This device's long-term X25519 identity (private key never leaves it).
class SyncIdentity {
  SyncIdentity({
    required this.deviceId,
    required this.privateKey,
    required this.publicKey,
  });

  final String deviceId;
  final Uint8List privateKey; // 32-byte X25519 seed
  final Uint8List publicKey; // 32 bytes

  static Future<SyncIdentity> generate(String deviceId) async {
    final seed = syncRandomBytes(32);
    final kp = await X25519().newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    return SyncIdentity(
      deviceId: deviceId,
      privateKey: seed,
      publicKey: Uint8List.fromList(pub.bytes),
    );
  }
}

/// Keys for one pair of devices, all derived from the X25519 shared secret.
class PairKeys {
  const PairKeys({
    required this.encKey,
    required this.pairId,
    required this.authToken,
  });

  /// AES-256-GCM key (stays on both devices only).
  final Uint8List encKey;

  /// Opaque relay mailbox id (HKDF output — reveals nothing).
  final String pairId;

  /// Bearer token; the relay keeps only its SHA-256.
  final String authToken;
}

/// ECDH(my private, peer public) → HKDF-SHA256 with a salt bound to both
/// device ids and both pairing nonces. Both sides derive identical keys.
Future<PairKeys> derivePairKeys({
  required SyncIdentity me,
  required String myNonce,
  required String peerId,
  required Uint8List peerPublicKey,
  required String peerNonce,
}) async {
  final algo = X25519();
  final kp = await algo.newKeyPairFromSeed(me.privateKey);
  final shared = await algo.sharedSecretKey(
    keyPair: kp,
    remotePublicKey: SimplePublicKey(peerPublicKey, type: KeyPairType.x25519),
  );
  final ikm = await shared.extractBytes();
  final parts = ['${me.deviceId}|$myNonce', '$peerId|$peerNonce']..sort();
  final salt = sha256Bytes(utf8.encode(parts.join('\n')));

  Future<Uint8List> hk(String info, int len) async {
    final k = await Hkdf(hmac: Hmac.sha256(), outputLength: len).deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: utf8.encode('inventory-sync/v1/$info'),
    );
    return Uint8List.fromList(await k.extractBytes());
  }

  return PairKeys(
    encKey: await hk('enc', 32),
    pairId: b64url(await hk('pair-id', 24)),
    authToken: b64url(await hk('auth', 32)),
  );
}

/// AES-256-GCM sealed message as stored on the relay.
class SealedBlob {
  const SealedBlob({required this.iv, required this.ct});
  final String iv; // base64 12-byte nonce
  final String ct; // base64 ciphertext || 16-byte tag
}

final _aes = AesGcm.with256bits();

Future<SealedBlob> sealBytes(
  List<int> clear, {
  required Uint8List key,
  required String aad,
}) async {
  final nonce = syncRandomBytes(12);
  final box = await _aes.encrypt(
    clear,
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: utf8.encode(aad),
  );
  return SealedBlob(iv: b64(nonce), ct: b64([...box.cipherText, ...box.mac.bytes]));
}

/// Throws [SecretBoxAuthenticationError] on a wrong key / tampered blob.
Future<Uint8List> openBytes(
  SealedBlob blob, {
  required Uint8List key,
  required String aad,
}) async {
  final all = unb64(blob.ct);
  if (all.length < 16) throw const FormatException('ciphertext too short');
  final box = SecretBox(
    all.sublist(0, all.length - 16),
    nonce: unb64(blob.iv),
    mac: Mac(all.sublist(all.length - 16)),
  );
  final clear = await _aes.decrypt(
    box,
    secretKey: SecretKey(key),
    aad: utf8.encode(aad),
  );
  return Uint8List.fromList(clear);
}

// ------------------------------------------------------------- v2 (groups)

final _ed = Ed25519();

/// This device's Ed25519 signing key (signs every group message; admins
/// also sign member lists). The private seed never leaves the device.
class SyncSigner {
  SyncSigner({required this.seed, required this.publicKey});
  final Uint8List seed; // 32 bytes
  final Uint8List publicKey; // 32 bytes

  static Future<SyncSigner> generate() async {
    final seed = syncRandomBytes(32);
    final kp = await _ed.newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    return SyncSigner(seed: seed, publicKey: Uint8List.fromList(pub.bytes));
  }

  Future<Uint8List> sign(List<int> message) async {
    final kp = await _ed.newKeyPairFromSeed(seed);
    final s = await _ed.sign(message, keyPair: kp);
    return Uint8List.fromList(s.bytes);
  }
}

/// True only for a valid Ed25519 signature of [message] by [publicKey].
Future<bool> syncVerify(
  List<int> message, {
  required List<int> signature,
  required List<int> publicKey,
}) async {
  if (signature.length != 64 || publicKey.length != 32) return false;
  try {
    return await _ed.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

/// AES key for messages between exactly two devices of a group (join
/// request, key hand-over): ECDH + HKDF bound to both ids and the group.
Future<Uint8List> deriveDirectKey({
  required SyncIdentity me,
  required String peerId,
  required Uint8List peerPublicKey,
  required String groupId,
  String purpose = 'direct',
}) async {
  final algo = X25519();
  final kp = await algo.newKeyPairFromSeed(me.privateKey);
  final shared = await algo.sharedSecretKey(
    keyPair: kp,
    remotePublicKey: SimplePublicKey(peerPublicKey, type: KeyPairType.x25519),
  );
  final ids = [me.deviceId, peerId]..sort();
  final k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(await shared.extractBytes()),
    nonce: sha256Bytes(utf8.encode('$groupId\n${ids.join('\n')}')),
    info: utf8.encode('inventory-sync/v2/$purpose'),
  );
  return Uint8List.fromList(await k.extractBytes());
}

/// HMAC-SHA256 (sender authentication tag inside group messages).
Future<Uint8List> hmacSha256(List<int> key, List<int> data) async {
  final m = await Hmac.sha256().calculateMac(data, secretKey: SecretKey(key));
  return Uint8List.fromList(m.bytes);
}

bool constantTimeEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}
