// Multi-device simulation through a LOCAL worker (never the deployed one):
//   cd sync-server
//   npx wrangler d1 execute inventory-sync --local --persist-to /tmp/wr-test --file=schema.sql
//   npx wrangler dev --local --persist-to /tmp/wr-test --test-scheduled
//   SYNC_LOCAL_URL=http://127.0.0.1:8787 flutter test test/sync/sync_group_local_worker_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Dev {
  Dev(this.db, this.engine, this.dir);
  final Database db;
  final SyncEngine engine;
  final Directory dir;

  Future<String> id() async => (await engine.identity()).deviceId;
  Future<int> items() async => (await db.query('inventory_items')).length;
  Future<Map<String, Object?>?> item(String id) async =>
      (await db.query('inventory_items', where: 'id = ?', whereArgs: [id])).firstOrNull;
  Future<GroupInfo> info() => engine.groupInfo();
}

void main() {
  final url = Platform.environment['SYNC_LOCAL_URL'];
  final skip = url == null ? 'set SYNC_LOCAL_URL to a local wrangler dev' : false;
  if (url != null && !(url.contains('127.0.0.1') || url.contains('localhost'))) {
    throw StateError('local worker only');
  }

  Future<Dev> dev() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) => AppDatabase.createSchema(d),
      ),
    );
    final dir = await Directory.systemTemp.createTemp('lw_photos');
    return Dev(
      db,
      SyncEngine(
        database: () async => db,
        transport: HttpSyncTransport(url!),
        photoDir: () async => dir.path,
      ),
      dir,
    );
  }

  Future<void> settle(List<Dev> ds) async {
    for (var i = 0; i < 6; i++) {
      var moved = 0;
      for (final d in ds) {
        final r = await d.engine.syncOnce();
        expect(r.offline, isFalse);
        moved += r.applied + r.pushed;
      }
      if (i > 1 && moved == 0) return;
    }
  }

  Future<void> join(Dev admin, Dev d, String name) async {
    await d.engine.joinGroup(GroupInvitePayload.tryParse(await admin.engine.createInvite())!);
    await admin.engine.syncOnce();
    final req = (await admin.info()).joins.firstWhere((j) => true);
    expect(req.deviceId, await d.id());
    await admin.engine.approveJoin(req.deviceId, name);
  }

  Future<void> edit(Dev d, String id, Map<String, Object?> v) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await d.db.update('inventory_items', {...v, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  test('4 devices: join, edit, photo, trash, promote, remove + key rotation, '
      'rejoin', () async {
    final a = await dev(), b = await dev(), c = await dev(), d = await dev();
    final now = DateTime.now().toIso8601String();
    await a.db.update('shop_settings', {'company_name': 'Local Shop'}, where: 'id = 1');
    await File(p.join(a.dir.path, 'bread.jpg')).writeAsBytes(List.generate(300000, (i) => i % 251));
    for (var i = 0; i < 30; i++) {
      await a.db.insert('inventory_items', {
        'id': 'i$i', 'title': 'Item $i', 'price': 1.5, 'amount': 10.0,
        'photo_path': i == 0 ? 'item_photos/bread.jpg' : null,
        'created_at': now, 'updated_at': now,
      });
    }
    await a.engine.createGroup();
    await join(a, b, 'Phone B');
    await join(a, c, 'Phone C');
    await settle([a, b, c]);
    for (final x in [b, c]) {
      expect(await x.items(), 30);
      expect((await x.db.query('shop_settings')).first['company_name'], 'Local Shop');
      expect(await File(p.join(x.dir.path, 'bread.jpg')).length(), 300000);
    }

    // Edits from a member reach everyone through the one mailbox.
    await edit(c, 'i1', {'amount': 3.0});
    await settle([a, b, c]);
    expect((await b.item('i1'))!['amount'], 3.0);

    // Member delete → trash on the admin → restore reaches everyone.
    await b.db.delete('inventory_items', where: 'id = ?', whereArgs: ['i2']);
    await settle([a, b, c]);
    expect(await c.item('i2'), isNull);
    final t = await a.engine.trash();
    expect(t.single.title, 'Item 2');
    await a.engine.restoreTrash([t.single.id]);
    await settle([a, b, c]);
    expect((await c.item('i2'))!['title'], 'Item 2');

    // Second admin, who then adds a 4th device.
    await a.engine.setMemberRole(await b.id(), admin: true);
    await settle([a, b, c]);
    expect((await b.info()).isAdmin, isTrue);
    await join(b, d, 'Tablet');
    await settle([a, b, c, d]);
    expect(await d.items(), 30);
    expect((await a.info()).activeMembers.length, 4);

    // Remove C: relay revokes, new key, C stops; C's later edit never lands.
    final epoch = (await a.info()).doc!.epoch;
    await a.engine.removeMember(await c.id());
    await settle([a, b, c, d]);
    expect((await c.info()).state, GroupState.removed);
    expect((await d.info()).doc!.epoch, isNot(epoch));
    await edit(c, 'i3', {'amount': 999.0});
    await edit(d, 'i4', {'amount': 7.0});
    await settle([a, b, c, d]);
    expect((await a.item('i3'))!['amount'], 10.0);
    expect((await b.item('i4'))!['amount'], 7.0);
    expect(await c.items(), 30, reason: 'removed device keeps its data');

    // C comes back with a fresh invite + Approve.
    await join(a, c, 'Phone C');
    await settle([a, b, c, d]);
    expect((await c.info()).state, GroupState.active);
    expect((await c.item('i4'))!['amount'], 7.0);

    // Last-admin guard on the real relay.
    await b.engine.setMemberRole(await a.id(), admin: false);
    await settle([a, b, c, d]);
    await expectLater(b.engine.setMemberRole(await b.id(), admin: false),
        throwsA(isA<GroupError>().having((e) => e.code, 'code', 'last_admin')));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('old pairing → group migration through the real worker', () async {
    final a = await dev(), b = await dev();
    final now = DateTime.now().toIso8601String();
    await a.db.insert('inventory_items', {
      'id': 'm1', 'title': 'Legacy', 'price': 1.0, 'amount': 2.0,
      'created_at': now, 'updated_at': now,
    });
    await b.engine.confirmPeer(PairingPayload.tryParse(await a.engine.pairingCode())!, 'A');
    await a.engine.confirmPeer(PairingPayload.tryParse(await b.engine.pairingCode())!, 'Phone B');
    await settle([a, b]);
    expect(await b.items(), 1);
    await a.engine.createGroup();
    await settle([a, b]);
    final j = (await a.info()).joins.single;
    expect(j.legacyName, 'Phone B');
    await a.engine.approveJoin(j.deviceId, j.legacyName!);
    await settle([a, b]);
    expect((await b.info()).state, GroupState.active);
    expect(await a.engine.peers(), isEmpty);
    await edit(b, 'm1', {'amount': 9.0});
    await settle([a, b]);
    expect((await a.item('m1'))!['amount'], 9.0);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
