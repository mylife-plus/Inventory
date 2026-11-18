import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/sync/sync_crypto.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';

import 'group_harness.dart';
import 'sync_test_harness.dart';

void main() {
  late DateTime now;
  late FakeGroupRelay relay;
  DateTime clock() => now;
  void tick([int s = 2]) => now = now.add(Duration(seconds: s));

  Future<TestDevice> device({DateTime Function()? clockFn}) =>
      TestDevice.create(relay, clock: clockFn ?? clock);

  Future<int> count(TestDevice d) async =>
      (await d.db.query('inventory_items')).length;

  Future<void> setAmount(TestDevice d, String id, double v) => d.db.update(
        'inventory_items',
        {'amount': v, 'updated_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// A + B + C in one group, A admin, shop data on A.
  Future<(TestDevice, TestDevice, TestDevice)> trio() async {
    final a = await device(), b = await device(), c = await device();
    await a.db.update('shop_settings', {'company_name': 'Bakery'}, where: 'id = 1');
    await a.addItem('i1', 'Bread', at: now);
    await a.addItem('i2', 'Milk', at: now);
    await a.engine.createGroup();
    await joinViaAdmin(a, b, name: 'Phone B');
    await joinViaAdmin(a, c, name: 'Phone C');
    await settleAll([a, b, c]);
    return (a, b, c);
  }

  setUp(() {
    now = DateTime.utc(2026, 11, 12, 10);
    relay = FakeGroupRelay(clock: clock);
  });

  group('member list', () {
    test('signed doc verifies; any change breaks it; ties pick one winner',
        () async {
      final s = await SyncSigner.generate();
      final other = await SyncSigner.generate();
      final doc = await MemberDoc(
        groupId: 'g' * 20,
        version: 3,
        epoch: 3001,
        issuedAt: 1,
        signer: 'd' * 20,
        members: [
          GroupMember(
            deviceId: 'd' * 20,
            name: 'A',
            role: 'admin',
            status: 'active',
            publicKey: syncRandomBytes(32),
            signKey: s.publicKey,
            addedAt: 1,
          ),
        ],
      ).signedBy(s);
      expect(await doc.verifiedBy(s.publicKey), isTrue);
      expect(await doc.verifiedBy(other.publicKey), isFalse);
      final round = MemberDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())))!;
      expect(await round.verifiedBy(s.publicKey), isTrue);
      final j = doc.toJson();
      (j['m']! as List).first['r'] = 'member';
      expect(await MemberDoc.fromJson(j)!.verifiedBy(s.publicKey), isFalse);
      final twin = await MemberDoc(
        groupId: doc.groupId, version: 3, epoch: 3002, issuedAt: 2,
        signer: doc.signer, members: doc.members,
      ).signedBy(s);
      expect(doc.beats(twin) != twin.beats(doc), isTrue);
    });

    test('invite QR round-trips; v1 codes and junk are not invites', () async {
      final inv = GroupInvitePayload(
        groupId: 'G' * 24, adminId: 'A' * 36, adminKey: syncRandomBytes(32),
        adminSignKey: syncRandomBytes(32), secret: 'S' * 24,
      );
      final back = GroupInvitePayload.tryParse(inv.encode())!;
      expect(back.groupId, inv.groupId);
      expect(back.adminSignKey, inv.adminSignKey);
      expect(GroupInvitePayload.tryParse('INVSYNC1:abc'), isNull);
      expect(GroupInvitePayload.tryParse('hello'), isNull);
    });
  });

  group('join', () {
    test('scan + one Approve: newcomer gets the whole shop; relay sees only '
        'ciphertext', () async {
      final (a, b, c) = await trio();
      for (final d in [b, c]) {
        expect(await count(d), 2);
        expect((await d.db.query('shop_settings')).first['company_name'], 'Bakery');
        expect(await stateOf(d), GroupState.active);
      }
      final info = await b.engine.groupInfo();
      expect(info.activeMembers.length, 3);
      expect(info.isAdmin, isFalse);
      expect(info.doc!.member((await c.engine.identity()).deviceId)!.name, 'Phone C');
      for (final blob in relay.everStoredGroup) {
        final raw = utf8.decode(base64Decode(blob.ct), allowMalformed: true);
        expect(raw.contains('Bread'), isFalse);
        expect(raw.contains('Bakery'), isFalse);
        expect(raw.contains('Phone C'), isFalse);
      }
    });

    test('a device waits (pending) until approved; edits flow both ways after',
        () async {
      final a = await device(), b = await device();
      await a.addItem('i1', 'Bread', at: now);
      await a.engine.createGroup();
      await b.engine.joinGroup(GroupInvitePayload.tryParse(await a.engine.createInvite())!);
      await settleAll([a, b]);
      expect(await stateOf(b), GroupState.joining);
      expect(await count(b), 0, reason: 'nothing before Approve');
      final req = (await a.engine.groupInfo()).joins.single;
      await a.engine.approveJoin(req.deviceId, 'Till 2');
      await settleAll([a, b]);
      expect(await count(b), 1);
      tick();
      await b.addItem('i2', 'Cake', at: now);
      await settleAll([a, b]);
      expect((await a.item('i2'))!['title'], 'Cake');
    });

    test('invite is single-use and expires', () async {
      final a = await device(), b = await device(), c = await device();
      await a.engine.createGroup();
      final code = GroupInvitePayload.tryParse(await a.engine.createInvite())!;
      await b.engine.joinGroup(code);
      await expectLater(c.engine.joinGroup(code),
          throwsA(isA<GroupError>().having((e) => e.code, 'code', 'invite_invalid')));
      final old = GroupInvitePayload.tryParse(await a.engine.createInvite())!;
      now = now.add(const Duration(minutes: 11));
      await expectLater(c.engine.joinGroup(old), throwsA(isA<GroupError>()));
    });

    test('declined request: device is told and can try again', () async {
      final a = await device(), b = await device();
      await a.engine.createGroup();
      await b.engine.joinGroup(GroupInvitePayload.tryParse(await a.engine.createInvite())!);
      await a.engine.syncOnce();
      await a.engine.rejectJoin((await a.engine.groupInfo()).joins.single.deviceId);
      await b.engine.syncOnce();
      expect(await stateOf(b), GroupState.none);
      expect(await b.engine.takeJoinDeclined(), isTrue);
      expect(await b.engine.takeJoinDeclined(), isFalse);
    });

    test('only admins can create invites or approve', () async {
      final (a, b, _) = await trio();
      await expectLater(b.engine.createInvite(),
          throwsA(isA<GroupError>().having((e) => e.code, 'code', 'not_admin')));
      final aId = (await a.engine.identity()).deviceId;
      await expectLater(b.engine.removeMember(aId), throwsA(isA<GroupError>()));
      await expectLater(b.engine.setMemberRole(aId, admin: false), throwsA(isA<GroupError>()));
    });
  });

  group('removal', () {
    test('removed device is cut off: 410, new key it never gets, data kept '
        'on its phone', () async {
      final (a, b, c) = await trio();
      final cId = (await c.engine.identity()).deviceId;
      final epochBefore = (await a.engine.groupInfo()).doc!.epoch;
      await a.engine.removeMember(cId);
      await settleAll([a, b, c]);
      expect(await stateOf(c), GroupState.removed);
      expect(await count(c), 2, reason: 'its local data stays');
      final docB = (await b.engine.groupInfo()).doc!;
      expect(docB.epoch, isNot(epochBefore));
      expect(docB.member(cId)!.isActive, isFalse);
      // Edits on C go nowhere; edits on A still reach B.
      tick();
      await setAmount(c, 'i1', 999);
      await setAmount(a, 'i2', 5);
      await settleAll([a, b, c]);
      expect((await b.item('i1'))!['amount'], 10);
      expect((await b.item('i2'))!['amount'], 5);
      expect((await c.item('i2'))!['amount'], 10, reason: 'C no longer receives');
    });

    test('what the device wrote before removal still counts; nothing after',
        () async {
      final (a, b, c) = await trio();
      tick();
      await setAmount(c, 'i1', 3); // pushed while still a member
      await c.engine.syncOnce();
      await a.engine.removeMember((await c.engine.identity()).deviceId);
      await settleAll([a, b]);
      expect((await b.item('i1'))!['amount'], 3);
    });

    test('a member can not relay edits authored by another device', () async {
      final (a, b, c) = await trio();
      final cId = (await c.engine.identity()).deviceId;
      await a.engine.removeMember(cId);
      await settleAll([a, b]);
      // B (non-admin) forwards an edit "by C" made after its removal.
      tick();
      await b.db.update('inventory_items', {'amount': 777.0}, where: 'id = ?', whereArgs: ['i1']);
      await b.engine.scanLocal();
      await b.db.update('sync_records', {'origin': cId, 'src': ''},
          where: 'kind = ? AND rid = ?', whereArgs: ['item', 'i1']);
      await b.engine.syncOnce();
      await a.engine.syncOnce();
      expect((await a.item('i1'))!['amount'], 10, reason: 'forged relay ignored');
    });

    test('tampered or wrongly signed member list is ignored', () async {
      final (a, b, c) = await trio();
      final bId = (await b.engine.identity()).deviceId;
      // C forges a list making itself admin and dropping A, signs it itself.
      final docC = (await c.engine.groupInfo()).doc!;
      final forged = await docC.next(
        signer: (await c.engine.identity()).deviceId,
        issuedAt: 1,
        members: [
          for (final m in docC.members)
            m.deviceId == (await c.engine.identity()).deviceId ? m.copyWith(role: 'admin') : m,
        ],
      ).signedBy(await c.engine.signer());
      final applied = await b.engine.applyForeignDocForTest(forged);
      expect(applied, isFalse);
      expect((await b.engine.groupInfo()).doc!.version, docC.version);
      expect((await b.engine.groupInfo()).doc!.member(bId)!.isActive, isTrue);
      expect(a, isNotNull);
    });

    test('member leaving: admins rotate the key without it', () async {
      final (a, b, c) = await trio();
      final cId = (await c.engine.identity()).deviceId;
      final e0 = (await a.engine.groupInfo()).doc!.epoch;
      await c.engine.leaveGroup();
      expect(await stateOf(c), GroupState.none);
      await settleAll([a, b]);
      final doc = (await b.engine.groupInfo()).doc!;
      expect(doc.member(cId)!.isActive, isFalse);
      expect(doc.epoch, isNot(e0));
    });
  });

  group('admin leaves = group deleted', () {
    test('every device is removed and keeps its data; the group is gone on '
        'the relay', () async {
      final (a, b, c) = await trio();
      // A second admin and a pending join are removed too.
      await a.engine.setMemberRole((await b.engine.identity()).deviceId, admin: true);
      await settleAll([a, b, c]);
      final d = await device();
      await d.engine.joinGroup(GroupInvitePayload.tryParse(await a.engine.createInvite())!);
      await a.engine.syncOnce();
      expect((await a.engine.groupInfo()).joins, hasLength(1));
      final gid = (await a.engine.groupInfo()).doc!.groupId;

      await a.engine.dissolveGroup();
      expect(await stateOf(a), GroupState.none);
      await settleAll([b, c, d]);
      expect(await stateOf(b), GroupState.removed);
      expect(await stateOf(c), GroupState.removed);
      expect(await stateOf(d), isNot(GroupState.active));
      for (final x in [a, b, c]) {
        expect(await count(x), 2, reason: 'data stays on every device');
      }
      expect(
        relay.devs[gid]!.values.where((v) => v.status != 'revoked'),
        isEmpty,
        reason: 'nobody is left in the group on the relay',
      );
      // Edits no longer travel between the former members.
      tick();
      await setAmount(b, 'i1', 42);
      await settleAll([a, b, c]);
      expect((await c.item('i1'))!['amount'], 10);
      expect((await a.item('i1'))!['amount'], 10);
    });
  });

  group('admins', () {
    test('one of two admins leaves: only that phone leaves, the group stays',
        () async {
      final (a, b, c) = await trio();
      final aId = (await a.engine.identity()).deviceId;
      await a.engine.setMemberRole((await b.engine.identity()).deviceId, admin: true);
      await settleAll([a, b, c]);
      await a.engine.leaveGroup();
      expect(await stateOf(a), GroupState.none);
      await settleAll([b, c]);
      expect(await stateOf(b), GroupState.active);
      expect(await stateOf(c), GroupState.active);
      final doc = (await b.engine.groupInfo()).doc!;
      expect(doc.member(aId)!.isActive, isFalse);
      expect((await b.engine.groupInfo()).isAdmin, isTrue);
      // B and C still sync with each other.
      tick();
      await setAmount(b, 'i1', 42);
      await settleAll([b, c]);
      expect((await c.item('i1'))!['amount'], 42);
    });

    test('promote/demote; the last admin can never step down', () async {
      final (a, b, _) = await trio();
      final aId = (await a.engine.identity()).deviceId;
      final bId = (await b.engine.identity()).deviceId;
      await expectLater(a.engine.setMemberRole(aId, admin: false),
          throwsA(isA<GroupError>().having((e) => e.code, 'code', 'last_admin')));
      await expectLater(a.engine.leaveGroup(),
          throwsA(isA<GroupError>().having((e) => e.code, 'code', 'last_admin')));
      await a.engine.setMemberRole(bId, admin: true);
      await settleAll([a, b]);
      expect((await b.engine.groupInfo()).isAdmin, isTrue);
      // B (now admin) can add a device and demote A.
      final d = await device();
      await joinViaAdmin(b, d, name: 'Tablet');
      await b.engine.setMemberRole(aId, admin: false);
      await settleAll([a, b, d]);
      expect(await count(d), 2);
      expect((await a.engine.groupInfo()).isAdmin, isFalse);
      await expectLater(a.engine.createInvite(), throwsA(isA<GroupError>()));
    });

    test('admin rename reaches every device', () async {
      final (a, b, c) = await trio();
      final cId = (await c.engine.identity()).deviceId;
      await a.engine.renameMember(cId, 'Counter 2');
      await settleAll([a, b, c]);
      expect((await b.engine.groupInfo()).doc!.member(cId)!.name, 'Counter 2');
    });
  });

  group('trash', () {
    test('delete by a non-admin: gone everywhere, restorable by the admin',
        () async {
      final (a, b, c) = await trio();
      tick();
      await b.db.delete('inventory_items', where: 'id = ?', whereArgs: ['i1']);
      await settleAll([a, b, c]);
      expect(await a.item('i1'), isNull);
      expect(await c.item('i1'), isNull);
      final t = await a.engine.trash();
      expect(t.single.title, 'Bread');
      expect(t.single.byDevice, (await b.engine.identity()).deviceId);
      tick();
      expect(await a.engine.restoreTrash([t.single.id]), 1);
      await settleAll([a, b, c]);
      for (final d in [a, b, c]) {
        expect((await d.item('i1'))!['title'], 'Bread');
      }
      expect(await a.engine.trash(), isEmpty);
    });

    test('admin deletes are final; category restore re-links its items',
        () async {
      final (a, b, c) = await trio();
      tick();
      await a.db.delete('inventory_items', where: 'id = ?', whereArgs: ['i2']);
      await b.db.insert('categories', {'id': 'cat1', 'name': 'Drinks'});
      await b.db.update('inventory_items', {'category_id': 'cat1'}, where: 'id = ?', whereArgs: ['i1']);
      await settleAll([a, b, c]);
      expect(await b.engine.trash(), isEmpty, reason: 'admin delete is not trashed');
      tick();
      await c.db.update('inventory_items', {'category_id': null}, where: 'category_id = ?', whereArgs: ['cat1']);
      await c.db.delete('categories', where: 'id = ?', whereArgs: ['cat1']);
      await settleAll([a, b, c]);
      final t = await a.engine.trash();
      expect(t.single.kind, 'cat');
      tick();
      await a.engine.restoreTrash([t.single.id]);
      await settleAll([a, b, c]);
      expect((await b.db.query('categories')).single['name'], 'Drinks');
      expect((await b.item('i1'))!['category_id'], 'cat1');
    });

    test('empty trash; entries older than 30 days drop off', () async {
      final (a, b, c) = await trio();
      tick();
      await b.db.delete('inventory_items');
      await settleAll([a, b, c]);
      expect((await a.engine.trash()).length, 2);
      now = now.add(const Duration(days: 31));
      await a.engine.syncOnce();
      expect(await a.engine.trash(), isEmpty);
    });
  });

  group('gaps and clocks', () {
    test('offline past relay retention: full resync from an admin', () async {
      final (a, b, c) = await trio();
      // C is offline for 70 days while A keeps editing.
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(days: 14));
        await a.addItem('n$i', 'New $i', at: now);
        await a.engine.syncOnce();
        await b.engine.syncOnce();
      }
      relay.purge(olderThanMs: 60 * 24 * 3600 * 1000);
      final before = await count(c);
      await settleAll([a, b, c]);
      await settleAll([a, b, c]);
      expect(before, 2);
      expect(await count(c), 7, reason: 'everything is back');
      expect(await count(b), 7);
    });

    test('a phone with its clock a day ahead does not win every conflict',
        () async {
      final (a, _, _) = await trio();
      var skewed = now.add(const Duration(days: 1));
      final d = await device(clockFn: () => skewed);
      await joinViaAdmin(a, d, name: 'Fast clock');
      await settleAll([a, d]);
      await d.engine.syncOnce(); // learns the relay time
      tick(5);
      skewed = skewed.add(const Duration(seconds: 5));
      await setAmount(d, 'i1', 1); // D edits first …
      await d.engine.syncOnce();
      tick(5);
      skewed = skewed.add(const Duration(seconds: 5));
      await setAmount(a, 'i1', 2); // … A edits later and must win
      await settleAll([a, d]);
      expect((await a.item('i1'))!['amount'], 2);
      expect((await d.item('i1'))!['amount'], 2);
    });

    test('edits stamped far in the future wait instead of winning', () async {
      final (a, b, _) = await trio();
      final future = now.add(const Duration(hours: 5)).millisecondsSinceEpoch;
      final applied = await b.engine.applyGroupChangesForTest(
        (await a.engine.identity()).deviceId,
        [SyncChange(kind: 'item', rid: 'i1', ts: future, origin: (await a.engine.identity()).deviceId,
            deleted: false, data: {'id': 'i1', 'title': 'Future', 'price': 1.0, 'amount': 1.0,
              'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String()})],
      );
      expect(applied, 0);
      expect((await b.item('i1'))!['title'], 'Bread');
      now = now.add(const Duration(hours: 5));
      await b.engine.syncOnce();
      expect((await b.item('i1'))!['title'], 'Future');
    });
  });

  group('migration from old pairs', () {
    test('first updated device becomes admin; paired device rejoins with one '
        'Approve; data intact', () async {
      final a = await device(), b = await device();
      await a.db.update('shop_settings', {'company_name': 'Bakery'}, where: 'id = 1');
      await a.addItem('i1', 'Bread', at: now);
      await pairDevices(a, b);
      await settle(a, b);
      tick();
      await b.addItem('i2', 'Cake', at: now);
      await settle(a, b);
      expect(await count(b), 2);

      await a.engine.createGroup();
      await settle(a, b); // invite travels through the old pair, B requests
      await a.engine.syncOnce();
      final join = (await a.engine.groupInfo()).joins.single;
      expect(join.legacyName, 'Phone B', reason: 'name from the old pairing');
      await a.engine.approveJoin(join.deviceId, join.legacyName!);
      await settleAll([a, b]);
      expect(await stateOf(b), GroupState.active);
      expect(await a.engine.peers(), isEmpty, reason: 'old pair retired');
      expect(await b.engine.peers(), isEmpty);
      expect(await count(a), 2);
      expect(await count(b), 2);
      expect((await b.db.query('shop_settings')).first['company_name'], 'Bakery');
      tick();
      await setAmount(b, 'i1', 4);
      await settleAll([a, b]);
      expect((await a.item('i1'))!['amount'], 4);
    });

    test('two devices that both started a group alone end in one', () async {
      final a = await device(), b = await device();
      await pairDevices(a, b);
      await settle(a, b);
      await a.engine.createGroup();
      await b.engine.createGroup();
      final ga = (await a.engine.groupInfo()).groupId!;
      final gb = (await b.engine.groupInfo()).groupId!;
      await settle(a, b);
      await settle(a, b);
      final loser = ga.compareTo(gb) < 0 ? b : a;
      final winner = identical(loser, a) ? b : a;
      expect(await stateOf(loser), GroupState.joining);
      expect((await loser.engine.groupInfo()).groupId, ga.compareTo(gb) < 0 ? ga : gb);
      await winner.engine.syncOnce();
      expect((await winner.engine.groupInfo()).joins, hasLength(1));
    });
  });

  test('server says revoked (410) → removed state; erase forgets the group',
      () async {
    final (a, b, _) = await trio();
    final bId = (await b.engine.identity()).deviceId;
    relay.devs.values.first[bId]!.status = 'revoked';
    await b.engine.syncOnce();
    expect(await stateOf(b), GroupState.removed);
    await a.engine.forgetEverything();
    expect(await stateOf(a), GroupState.none);
    expect(relay.devs.values.first.values.where((d) => d.status == 'active'), isNotEmpty);
    expect(SyncServerException, isNotNull);
  });
}
