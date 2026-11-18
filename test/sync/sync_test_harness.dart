import 'dart:io';

import 'package:inventory_app/core/sync/sync_crypto.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory relay with the Worker's semantics (per-pair mailbox, sender
/// filter, ack-on-pull cleanup, auth registered on first use).
class FakeRelay implements SyncTransport {
  final Map<String, List<(int, String, SealedBlob)>> boxes = {};
  final Map<String, String> auth = {};
  final Set<String> closed = {};
  final List<SealedBlob> everStored = [];
  var _seq = 0;
  bool offline = false;

  void _auth(String pairId, String token) {
    if (offline) throw const SyncOfflineException();
    final known = auth.putIfAbsent(pairId, () => token);
    if (known != token) throw const SyncServerException(401, 'unauthorized');
    if (closed.contains(pairId)) {
      throw const SyncServerException(410, 'pair_closed');
    }
  }

  @override
  Future<List<int>> push({
    required String pairId,
    required String auth,
    required String sender,
    required List<SealedBlob> blobs,
  }) async {
    _auth(pairId, auth);
    final out = <int>[];
    for (final b in blobs) {
      (boxes[pairId] ??= []).add((++_seq, sender, b));
      everStored.add(b);
      out.add(_seq);
    }
    return out;
  }

  @override
  Future<PullPage> pull({
    required String pairId,
    required String auth,
    required String device,
    required int after,
  }) async {
    _auth(pairId, auth);
    final box = boxes[pairId] ??= [];
    box.removeWhere((e) => e.$2 != device && e.$1 <= after);
    return PullPage([
      for (final e in box)
        if (e.$2 != device && e.$1 > after) PulledBlob(e.$1, e.$3),
    ]);
  }

  @override
  Future<void> drop({required String pairId, required String auth}) async {
    if (closed.contains(pairId)) return;
    _auth(pairId, auth);
    boxes.remove(pairId);
    closed.add(pairId);
  }
}

class TestDevice {
  TestDevice._(this.db, this.engine, this.photos);
  final Database db;
  final SyncEngine engine;
  final Directory photos;

  static Future<TestDevice> create(
    FakeRelay relay, {
    required DateTime Function() clock,
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          await AppDatabase.createSchema(d);
        },
      ),
    );
    final photos = await Directory.systemTemp.createTemp('sync_photos');
    final engine = SyncEngine(
      database: () async => db,
      transport: relay,
      photoDir: () async => photos.path,
      clock: clock,
    );
    return TestDevice._(db, engine, photos);
  }

  Future<String> code() => engine.pairingCode();

  Future<void> addItem(
    String id,
    String title, {
    double price = 1,
    double amount = 10,
    String? categoryId,
    String? photo,
    required DateTime at,
  }) =>
      db.insert('inventory_items', {
        'id': id,
        'title': title,
        'price': price,
        'amount': amount,
        'category_id': categoryId,
        'photo_path': photo,
        'created_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
      });

  Future<Map<String, Object?>?> item(String id) async {
    final r = await db.query('inventory_items', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }
}

/// Mutual scan + both sides confirm.
Future<void> pairDevices(TestDevice a, TestDevice b) async {
  final codeA = PairingPayload.tryParse(await a.code())!;
  final codeB = PairingPayload.tryParse(await b.code())!;
  await b.engine.confirmPeer(codeA, 'Counter A');
  await a.engine.confirmPeer(codeB, 'Phone B');
}

/// Run sync rounds on both until nothing moves.
Future<void> settle(TestDevice a, TestDevice b) async {
  for (var i = 0; i < 6; i++) {
    final ra = await a.engine.syncOnce();
    final rb = await b.engine.syncOnce();
    if (i > 1 && ra.applied + rb.applied + ra.pushed + rb.pushed == 0) return;
  }
}
