import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/sync/sync_crypto.dart';
import 'package:inventory_app/core/sync/sync_merge.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:path/path.dart' as p;

import 'sync_test_harness.dart';

bool _containsBytes(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  var now = DateTime(2026, 11, 10, 9);
  DateTime clock() => now;

  group('pairing payload', () {
    test('round-trips and rejects anything that is not a sync code', () async {
      final me = await SyncIdentity.generate('8c1b2f9e-0000-4000-8000-123456789abc');
      final code = PairingPayload(
        deviceId: me.deviceId,
        publicKey: me.publicKey,
        nonce: 'abcDEF123_-x',
      ).encode();
      expect(code, startsWith('INVSYNC1:'));
      final back = PairingPayload.tryParse(code)!;
      expect(back.deviceId, me.deviceId);
      expect(back.publicKey, me.publicKey);
      expect(back.nonce, 'abcDEF123_-x');
      expect(back.appName, 'Inventory');

      for (final bad in [
        null,
        '',
        'hello',
        'https://example.com',
        'INVSYNC1:',
        'INVSYNC1:!!!notbase64',
        'INVSYNC1:${b64url(utf8.encode(jsonEncode({'d': 'short', 'k': b64(me.publicKey), 'n': 'abcdefgh'})))}',
        'INVSYNC1:${b64url(utf8.encode(jsonEncode({'d': me.deviceId, 'k': b64([1, 2, 3]), 'n': 'abcdefgh'})))}',
        'INVSYNC1:${b64url(utf8.encode(jsonEncode({'d': me.deviceId, 'k': b64(me.publicKey), 'n': 'x'})))}',
        code.substring(0, code.length - 6),
      ]) {
        expect(PairingPayload.tryParse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('crypto', () {
    test('both sides derive the same keys; AES-GCM round-trip; tamper fails',
        () async {
      final a = await SyncIdentity.generate('aaaaaaaa-0000-4000-8000-000000000001');
      final b = await SyncIdentity.generate('bbbbbbbb-0000-4000-8000-000000000002');
      final ka = await derivePairKeys(
          me: a, myNonce: 'nonceAAAA', peerId: b.deviceId,
          peerPublicKey: b.publicKey, peerNonce: 'nonceBBBB');
      final kb = await derivePairKeys(
          me: b, myNonce: 'nonceBBBB', peerId: a.deviceId,
          peerPublicKey: a.publicKey, peerNonce: 'nonceAAAA');
      expect(ka.encKey, kb.encKey);
      expect(ka.pairId, kb.pairId);
      expect(ka.authToken, kb.authToken);
      expect(ka.pairId, matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')));
      expect(ka.authToken, isNot(contains(b64(ka.encKey))));

      // A different nonce (re-pair) gives different keys.
      final k2 = await derivePairKeys(
          me: a, myNonce: 'nonceZZZZ', peerId: b.deviceId,
          peerPublicKey: b.publicKey, peerNonce: 'nonceBBBB');
      expect(k2.encKey, isNot(ka.encKey));

      final clear = utf8.encode('{"title":"Bread","price":2.5}');
      final sealed = await sealBytes(clear, key: ka.encKey, aad: ka.pairId);
      expect(await openBytes(sealed, key: kb.encKey, aad: kb.pairId), clear);
      // Fresh nonce per message.
      final again = await sealBytes(clear, key: ka.encKey, aad: ka.pairId);
      expect(again.iv, isNot(sealed.iv));
      expect(again.ct, isNot(sealed.ct));

      await expectLater(
        openBytes(sealed, key: k2.encKey, aad: ka.pairId),
        throwsA(anything),
      );
      await expectLater(
        openBytes(sealed, key: ka.encKey, aad: 'other-pair'),
        throwsA(anything),
      );
      final raw = unb64(sealed.ct)..[0] ^= 1;
      await expectLater(
        openBytes(SealedBlob(iv: sealed.iv, ct: b64(raw)),
            key: ka.encKey, aad: ka.pairId),
        throwsA(anything),
      );
    });
  });

  group('last-write-wins', () {
    test('newer edit wins; ties break the same way on both devices', () {
      expect(remoteWins(localTs: 10, localOrigin: 'a', remoteTs: 11, remoteOrigin: 'a'), isTrue);
      expect(remoteWins(localTs: 11, localOrigin: 'a', remoteTs: 10, remoteOrigin: 'z'), isFalse);
      // Tie: device b wins on BOTH sides.
      expect(remoteWins(localTs: 5, localOrigin: 'a', remoteTs: 5, remoteOrigin: 'b'), isTrue);
      expect(remoteWins(localTs: 5, localOrigin: 'b', remoteTs: 5, remoteOrigin: 'a'), isFalse);
      expect(remoteWins(localTs: 5, localOrigin: 'a', remoteTs: 5, remoteOrigin: 'a'), isFalse);
      expect(nextEditTs(100, 50), 100);
      expect(nextEditTs(100, 500), 501, reason: 'peer clock ahead');
      expect(recordHash({'b': 1, 'a': 2}), recordHash({'a': 2, 'b': 1}));
    });
  });

  group('two devices (in-memory relay)', () {
    late FakeRelay relay;
    late TestDevice a;
    late TestDevice b;

    setUp(() async {
      now = DateTime(2026, 11, 10, 9);
      relay = FakeRelay();
      a = await TestDevice.create(relay, clock: clock);
      b = await TestDevice.create(relay, clock: clock);
    });

    tearDown(() async {
      await a.db.close();
      await b.db.close();
    });

    test('pair → full shop copies to the new device, encrypted on the relay',
        () async {
      await a.db.update('shop_settings', {'company_name': 'Ali Bakery', 'city': 'Lahore'}, where: 'id = 1');
      await b.db.update('shop_settings', {'company_name': 'New phone'}, where: 'id = 1');
      await a.db.insert('categories', {'id': 'c1', 'name': 'Bakery'});
      final photoBytes = Uint8List.fromList(List.generate(300000, (i) => i % 251));
      await File(p.join(a.photos.path, 'i1_1.jpg')).writeAsBytes(photoBytes);
      await a.addItem('i1', 'Secret Bread', categoryId: 'c1', photo: 'item_photos/i1_1.jpg', at: DateTime(2026, 11, 1));
      await a.db.insert('customers', {'id': 'u1', 'name': 'Zainab Customer', 'created_at': DateTime(2026, 10, 1).toIso8601String()});
      await a.db.insert('sales', {'id': 's1', 'customer_id': 'u1', 'customer_name': 'Zainab Customer', 'total': 5.0, 'created_at': DateTime(2026, 11, 2).toIso8601String()});
      await a.db.insert('sale_lines', {'sale_id': 's1', 'item_id': 'i1', 'title': 'Secret Bread', 'unit_price': 2.5, 'quantity': 2.0, 'unit': null});

      await pairDevices(a, b);
      await settle(a, b);

      expect((await a.engine.peers()).single.isActive, isTrue);
      expect((await b.engine.peers()).single.isActive, isTrue);
      expect((await b.engine.peers()).single.name, 'Counter A');
      expect((await b.item('i1'))!['title'], 'Secret Bread');
      expect((await b.item('i1'))!['category_id'], 'c1');
      final shopB = (await b.db.query('shop_settings')).first;
      expect(shopB['company_name'], 'Ali Bakery', reason: 'filled shop with data wins first pairing');
      expect(shopB['city'], 'Lahore');
      expect((await b.db.query('customers')).single['name'], 'Zainab Customer');
      final lines = await b.db.query('sale_lines');
      expect(lines.single['quantity'], 2.0);
      expect((await b.db.query('sales')).single['customer_id'], 'u1');
      expect(await File(p.join(b.photos.path, 'i1_1.jpg')).readAsBytes(), photoBytes);

      // Relay only ever held ciphertext: no titles, names or ids in clear.
      expect(relay.everStored, isNotEmpty);
      for (final blob in relay.everStored) {
        final bytes = base64Decode(blob.ct);
        for (final secret in ['Secret Bread', 'Zainab', 'Ali Bakery', 'Lahore', 'Counter A', 'Phone B', 'i1_1.jpg']) {
          expect(blob.ct.contains(secret), isFalse);
          expect(_containsBytes(bytes, utf8.encode(secret)), isFalse, reason: secret);
        }
        expect(_containsBytes(bytes, photoBytes.sublist(1000, 1032)), isFalse);
      }

      // Then live: edit on B shows on A.
      now = now.add(const Duration(minutes: 1));
      await b.db.update('inventory_items', {'amount': 7.0}, where: 'id = ?', whereArgs: ['i1']);
      await settle(a, b);
      expect((await a.item('i1'))!['amount'], 7.0);
    });

    test('pair stays pending until BOTH devices scanned and confirmed', () async {
      await a.addItem('i1', 'Bread', at: DateTime(2026, 11, 1));
      final codeA = PairingPayload.tryParse(await a.code())!;
      await b.engine.confirmPeer(codeA, 'A');
      await settle(a, b);
      expect((await b.engine.peers()).single.isActive, isFalse);
      expect(await a.engine.peers(), isEmpty);
      expect(await b.item('i1'), isNull);
      // Own code is rejected.
      await expectLater(b.engine.confirmPeer(PairingPayload.tryParse(await b.code())!, 'me'), throwsArgumentError);
      // Now A scans B too → both active, data flows.
      await a.engine.confirmPeer(PairingPayload.tryParse(await b.code())!, 'B');
      await settle(a, b);
      expect((await a.engine.peers()).single.isActive, isTrue);
      expect((await b.item('i1'))!['title'], 'Bread');
    });

    test('offline edits on both: last edit wins on both devices', () async {
      await a.addItem('i1', 'Bread', price: 2.5, at: DateTime(2026, 11, 1));
      await pairDevices(a, b);
      await settle(a, b);

      relay.offline = true;
      now = DateTime(2026, 11, 10, 10, 0);
      await a.db.update('inventory_items', {'price': 3.0}, where: 'id = ?', whereArgs: ['i1']);
      final ra = await a.engine.syncOnce();
      expect(ra.offline, isTrue);
      now = DateTime(2026, 11, 10, 10, 5);
      await b.db.update('inventory_items', {'price': 4.0}, where: 'id = ?', whereArgs: ['i1']);
      await b.engine.syncOnce();
      expect((await a.item('i1'))!['price'], 3.0, reason: 'offline sync never touches data');

      relay.offline = false;
      now = DateTime(2026, 11, 10, 10, 6);
      await settle(a, b);
      expect((await a.item('i1'))!['price'], 4.0);
      expect((await b.item('i1'))!['price'], 4.0);

      // Later delete on A wins too.
      now = DateTime(2026, 11, 10, 11);
      await a.db.delete('inventory_items', where: 'id = ?', whereArgs: ['i1']);
      await settle(a, b);
      expect(await b.item('i1'), isNull);
    });

    test('garbage on the relay is skipped and never wipes data', () async {
      await a.addItem('i1', 'Bread', at: DateTime(2026, 11, 1));
      await pairDevices(a, b);
      await settle(a, b);
      final pairId = relay.boxes.keys.single;
      await relay.push(pairId: pairId, auth: relay.auth[pairId]!, sender: 'attacker-0000000000', blobs: [
        SealedBlob(iv: b64(syncRandomBytes(12)), ct: b64(syncRandomBytes(64))),
      ]);
      final r = await b.engine.syncOnce();
      expect(r.ok, isTrue);
      expect((await b.item('i1'))!['title'], 'Bread');
    });

    test('mass-wipe guard: an empty DB never broadcasts 25 deletions', () async {
      for (var i = 0; i < 25; i++) {
        await a.addItem('i$i', 'Item $i', at: DateTime(2026, 11, 1));
      }
      await pairDevices(a, b);
      await settle(a, b);
      expect((await b.db.query('inventory_items')).length, 25);
      now = now.add(const Duration(minutes: 5));
      await a.db.delete('inventory_items');
      await settle(a, b);
      expect((await b.db.query('inventory_items')).length, 25);
    });

    test('same category name on both devices merges into one', () async {
      await a.db.insert('categories', {'id': 'ca', 'name': 'Drinks'});
      await b.db.insert('categories', {'id': 'cb', 'name': 'drinks'});
      await b.addItem('ib', 'Cola', categoryId: 'cb', at: DateTime(2026, 11, 1));
      await pairDevices(a, b);
      await settle(a, b);
      final ca = await a.db.query('categories');
      final cb = await b.db.query('categories');
      expect(ca.length, 1);
      expect(cb.length, 1);
      expect(ca.single['id'], cb.single['id']);
      expect((await a.item('ib'))!['category_id'], ca.single['id']);
      expect((await b.item('ib'))!['category_id'], cb.single['id']);
    });

    test('unpair drops the relay mailbox and keeps local data', () async {
      await a.addItem('i1', 'Bread', at: DateTime(2026, 11, 1));
      await pairDevices(a, b);
      await settle(a, b);
      final peerB = (await a.engine.peers()).single;
      await a.engine.removePeer(peerB.peerId);
      expect(await a.engine.peers(), isEmpty);
      expect(relay.boxes, isEmpty);
      expect((await a.item('i1'))!['title'], 'Bread');
      // The other side learns it on its next sync, keeps its data and
      // stops pushing into the closed mailbox.
      await b.addItem('i2', 'Milk', at: DateTime(2026, 11, 2));
      final rb = await b.engine.syncOnce();
      expect(rb.error, isNull);
      expect((await b.engine.peers()).single.status, 'removed');
      expect((await b.item('i1'))!['title'], 'Bread');
      expect(relay.boxes, isEmpty);
      // Pairing again works (fresh pair id because A rotated its nonce).
      await b.engine.removePeer((await b.engine.peers()).single.peerId);
      await pairDevices(a, b);
      await settle(a, b);
      expect((await a.engine.peers()).single.isActive, isTrue);
      expect((await a.item('i2'))!['title'], 'Milk');
      // Erase data forgets identity: a new device id afterwards.
      final before = (await a.engine.identity()).deviceId;
      await a.engine.forgetEverything();
      expect((await a.engine.identity()).deviceId, isNot(before));
      expect((await a.db.query('sync_peers')), isEmpty);
    });
  });
}
