// Live check against the deployed relay. Skipped unless SYNC_LIVE=1:
//   SYNC_LIVE=1 flutter test test/sync/sync_live_worker_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/sync/sync_config.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<(Database, SyncEngine, Directory)> _device(SyncTransport t) async {
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
  final dir = await Directory.systemTemp.createTemp('live_photos');
  return (
    db,
    SyncEngine(
      database: () async => db,
      transport: t,
      photoDir: () async => dir.path,
    ),
    dir,
  );
}

void main() {
  final live = Platform.environment['SYNC_LIVE'] == '1';
  test('two devices sync through the real Cloudflare relay', () async {
    final t = HttpSyncTransport(kSyncServerUrl);
    final (dbA, a, dirA) = await _device(t);
    final (dbB, b, dirB) = await _device(t);
    await dbA.update('shop_settings', {'company_name': 'Live Test Shop'}, where: 'id = 1');
    await File(p.join(dirA.path, 'live_1.jpg')).writeAsBytes(List.generate(1200000, (i) => i % 256));
    await dbA.insert('inventory_items', {
      'id': 'live-item', 'title': 'Live Bread', 'price': 2.5, 'amount': 3.0,
      'photo_path': 'item_photos/live_1.jpg',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await b.confirmPeer(PairingPayload.tryParse(await a.pairingCode())!, 'A');
    await a.confirmPeer(PairingPayload.tryParse(await b.pairingCode())!, 'B');
    for (var i = 0; i < 4; i++) {
      final ra = await a.syncOnce();
      final rb = await b.syncOnce();
      expect(ra.ok && rb.ok, isTrue, reason: '${ra.error} ${rb.error}');
    }
    final item = (await dbB.query('inventory_items')).single;
    expect(item['title'], 'Live Bread');
    expect((await dbB.query('shop_settings')).first['company_name'], 'Live Test Shop');
    expect(await File(p.join(dirB.path, 'live_1.jpg')).length(), 1200000);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await dbB.update('inventory_items', {'amount': 1.0}, where: 'id = ?', whereArgs: ['live-item']);
    await b.syncOnce();
    await a.syncOnce();
    expect((await dbA.query('inventory_items')).single['amount'], 1.0);

    // Clean up the relay mailbox.
    await a.removePeer((await a.peers()).single.peerId);
    await b.removePeer((await b.peers()).single.peerId);
  }, skip: live ? false : 'set SYNC_LIVE=1 to hit the deployed relay', timeout: const Timeout(Duration(minutes: 2)));
}
