import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:inventory_app/core/sync/sync_crypto.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/sync/sync_merge.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_store.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

part 'sync_group_engine.dart';

/// One paired device (name stays on this device only).
class SyncPeer {
  const SyncPeer({
    required this.peerId,
    required this.name,
    required this.status,
    required this.createdAt,
    this.lastSyncAt,
    this.lastError,
  });

  final String peerId;
  final String name;

  /// `pending` until the other device has scanned us and confirmed too;
  /// `removed` once the other device unpaired (nothing syncs any more).
  final String status;
  final DateTime createdAt;
  final DateTime? lastSyncAt;
  final String? lastError;

  bool get isActive => status == 'active';
  bool get isRemoved => status == 'removed';

  static SyncPeer fromRow(Map<String, Object?> r) => SyncPeer(
        peerId: r['peer_id']! as String,
        name: r['name']! as String,
        status: r['status']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        lastSyncAt: r['last_sync_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['last_sync_at']! as int),
        lastError: r['last_error'] as String?,
      );
}

class SyncRunResult {
  const SyncRunResult({
    this.applied = 0,
    this.pushed = 0,
    this.offline = false,
    this.error,
  });
  final int applied;
  final int pushed;
  final bool offline;
  final Object? error;
  bool get ok => !offline && error == null;
}

/// One record version in transit (inside an encrypted message only).
class SyncChange {
  SyncChange({
    required this.kind,
    required this.rid,
    required this.ts,
    required this.origin,
    required this.deleted,
    this.data,
  });

  final String kind;
  final String rid;
  final int ts;
  final String origin;
  final bool deleted;
  final Object? data;

  Map<String, Object?> toJson() => {
        'k': kind,
        'r': rid,
        't': ts,
        'o': origin,
        if (deleted) 'x': 1,
        if (!deleted) 'd': data,
      };

  static SyncChange? fromJson(Object? j) {
    if (j is! Map) return null;
    final k = j['k'], r = j['r'], t = j['t'], o = j['o'];
    if (k is! String || r is! String || t is! num || o is! String) return null;
    if (!kSyncKinds.contains(k)) return null;
    return SyncChange(
      kind: k,
      rid: r,
      ts: t.toInt(),
      origin: o,
      deleted: j['x'] == 1,
      data: j['d'],
    );
  }
}

/// Encrypted change-feed sync between paired devices.
///
/// Every scan hashes each synced record and compares it with
/// `sync_records`; anything new/changed/removed gets a new edit time and a
/// local sequence number. Pushing sends records past each peer's cursor
/// (encrypted per pair); pulling applies remote versions with
/// last-write-wins per record. Nothing is ever deleted locally except by an
/// explicit tombstone that wins LWW — a failed sync never touches data.
class SyncEngine {
  SyncEngine({
    required Future<Database> Function() database,
    required this.transport,
    required Future<String?> Function() photoDir,
    DateTime Function()? clock,
    GroupTransport? groupTransport,
  })  : _database = database,
        _photoDir = photoDir,
        _clock = clock ?? DateTime.now,
        _groupTransport = groupTransport ??
            (transport is GroupTransport ? transport as GroupTransport : null);

  final Future<Database> Function() _database;
  final Future<String?> Function() _photoDir;
  final SyncTransport transport;
  final DateTime Function() _clock;
  final GroupTransport? _groupTransport;

  SyncSigner? _signer;

  /// Relay clock minus this device's clock, when they differ by more than a
  /// minute: edit times then follow the relay (a phone set a day ahead no
  /// longer wins every conflict).
  int _clockOffset = 0;
  bool _offsetLoaded = false;
  final Map<String, int> _resyncServed = {};

  /// X25519-derived keys per (group, device, purpose): the scalar
  /// multiplication is slow in pure Dart, the result never changes.
  final Map<String, Uint8List> _pairKeyCache = {};

  static const _photoFolder = 'item_photos';
  static const _msgLimit = 200 * 1024; // plaintext JSON per message
  static const _requestLimit = 8 * 1024 * 1024; // ciphertext per push

  SyncIdentity? _identity;
  final Map<String, Set<String>> _columns = {};

  int get _now => _clock().millisecondsSinceEpoch + _clockOffset;

  Future<Database> _db() async {
    final db = await _database();
    await ensureSyncTables(db);
    return db;
  }

  // ---------------------------------------------------------------- identity

  Future<String?> _meta(DatabaseExecutor db, String k) async {
    final r = await db.query('sync_meta', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String;
  }

  Future<void> _setMeta(DatabaseExecutor db, String k, String v) => db.insert(
        'sync_meta',
        {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<SyncIdentity> identity() async {
    final db = await _db();
    final cached = _identity;
    if (cached != null) {
      // Erase Data wipes the identity through another engine instance; a
      // stale cached id here made this phone pair under its old id and then
      // talk under a new one after a restart, so the other phone ignored it
      // and stayed "waiting" (⏳) forever. Always follow the database.
      if (await _meta(db, 'device_id') == cached.deviceId) return cached;
      _identity = null;
    }
    final id = await _meta(db, 'device_id');
    final priv = await _meta(db, 'private_key');
    final pub = await _meta(db, 'public_key');
    if (id != null && priv != null && pub != null) {
      return _identity = SyncIdentity(
        deviceId: id,
        privateKey: unb64(priv),
        publicKey: unb64(pub),
      );
    }
    final fresh = await SyncIdentity.generate(const Uuid().v4());
    // Two first calls at once must not leave two different identities.
    final saved = await db.transaction((txn) async {
      final id2 = await _meta(txn, 'device_id');
      final priv2 = await _meta(txn, 'private_key');
      final pub2 = await _meta(txn, 'public_key');
      if (id2 != null && priv2 != null && pub2 != null) {
        return SyncIdentity(
          deviceId: id2,
          privateKey: unb64(priv2),
          publicKey: unb64(pub2),
        );
      }
      await _setMeta(txn, 'device_id', fresh.deviceId);
      await _setMeta(txn, 'private_key', b64(fresh.privateKey));
      await _setMeta(txn, 'public_key', b64(fresh.publicKey));
      return fresh;
    });
    return _identity = saved;
  }

  Future<String> _myNonce(DatabaseExecutor db, {bool rotate = false}) async {
    var n = rotate ? null : await _meta(db, 'pair_nonce');
    if (n == null) {
      n = b64url(syncRandomBytes(12));
      await _setMeta(db, 'pair_nonce', n);
    }
    return n;
  }

  /// Text for this device's pairing QR.
  Future<String> pairingCode() async {
    final me = await identity();
    final db = await _db();
    return PairingPayload(
      deviceId: me.deviceId,
      publicKey: me.publicKey,
      nonce: await _myNonce(db),
    ).encode();
  }

  // ------------------------------------------------------------------- peers

  Future<List<SyncPeer>> peers() async {
    final db = await _db();
    final rows = await db.query('sync_peers', orderBy: 'created_at');
    return rows.map(SyncPeer.fromRow).toList();
  }

  /// This side confirmed the scanned device and its name. The pair turns
  /// `active` once the other side has scanned us and confirmed as well
  /// (its encrypted hello arrives).
  Future<SyncPeer> confirmPeer(PairingPayload scanned, String name) async {
    final me = await identity();
    if (scanned.deviceId == me.deviceId) {
      throw ArgumentError('own code');
    }
    final db = await _db();
    final myNonce = await _myNonce(db);
    final keys = await derivePairKeys(
      me: me,
      myNonce: myNonce,
      peerId: scanned.deviceId,
      peerPublicKey: scanned.publicKey,
      peerNonce: scanned.nonce,
    );
    final row = <String, Object?>{
      'peer_id': scanned.deviceId,
      'name': name.trim().isEmpty ? 'Device' : name.trim(),
      'public_key': b64(scanned.publicKey),
      'peer_nonce': scanned.nonce,
      'my_nonce': myNonce,
      'enc_key': b64(keys.encKey),
      'pair_id': keys.pairId,
      'auth': keys.authToken,
      'status': 'pending',
      'created_at': _now,
      'pushed_lseq': 0,
      'pulled_seq': 0,
      'hello_sent': 0,
    };
    await db.insert(
      'sync_peers',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return SyncPeer.fromRow(row);
  }

  Future<void> renamePeer(String peerId, String name) async {
    final db = await _db();
    await db.update(
      'sync_peers',
      {'name': name.trim()},
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
  }

  /// Unpair: ask the relay to drop this pair's ciphertext (best effort),
  /// then forget the key locally. Local shop data is kept.
  Future<void> removePeer(String peerId) async {
    final db = await _db();
    final rows = await db.query(
      'sync_peers',
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
    if (rows.isNotEmpty) {
      try {
        await transport.drop(
          pairId: rows.first['pair_id']! as String,
          auth: rows.first['auth']! as String,
        );
      } catch (_) {}
    }
    await db.delete('sync_peers', where: 'peer_id = ?', whereArgs: [peerId]);
    await _myNonce(db, rotate: true);
    final left = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_peers'),
    );
    if ((left ?? 0) == 0 && await _gState(db) == GroupState.none) {
      // Fresh baseline next time a device is paired.
      await db.delete('sync_records');
      await db.delete('sync_meta', where: 'k = ?', whereArgs: ['baseline']);
    }
  }

  /// Erase Data: drop every pair on the relay (short, best effort) and
  /// forget identity + keys.
  Future<void> forgetEverything() async {
    final db = await _db();
    final auth = await _auth(db);
    if (auth != null && _groupTransport != null) {
      try {
        await _groupTransport.leave(auth);
      } catch (_) {}
    }
    final rows = await db.query('sync_peers');
    for (final r in rows) {
      try {
        await transport.drop(
          pairId: r['pair_id']! as String,
          auth: r['auth']! as String,
        );
      } catch (_) {}
    }
    await wipeSyncTables(db);
    _identity = null;
  }

  // -------------------------------------------------------------- snapshot

  Future<Set<String>> _cols(DatabaseExecutor db, String table) async {
    final c = _columns[table];
    if (c != null) return c;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return _columns[table] = {for (final r in rows) r['name']! as String};
  }

  static int _parseTs(Object? v) {
    if (v is! String) return 0;
    return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
  }

  /// Current synced records: key `kind/rid` → (data, intrinsic ts).
  Future<Map<String, ({Object? data, int baseTs})>> _snapshot(
    DatabaseExecutor db,
  ) async {
    final out = <String, ({Object? data, int baseTs})>{};
    final shop = await db.query('shop_settings', where: 'id = 1');
    final items = await db.query('inventory_items', orderBy: 'id');
    final sales = await db.query('sales', orderBy: 'id');
    if (shop.isNotEmpty) {
      final s = Map<String, Object?>.from(shop.first)..remove('id');
      final named = '${s['company_name'] ?? ''}'.trim().isNotEmpty;
      // First pairing: the filled-in shop with more data wins over an
      // empty/new one (real edits later get wall-clock times).
      out['shop/1'] = (
        data: s,
        baseTs: named ? 1 + items.length + sales.length : 0,
      );
    }
    for (final r in await db.query('categories', orderBy: 'id')) {
      out['cat/${r['id']}'] = (data: r, baseTs: 0);
    }
    for (final r in await db.query('customers', orderBy: 'id')) {
      out['cust/${r['id']}'] = (data: r, baseTs: _parseTs(r['created_at']));
    }
    for (final r in items) {
      out['item/${r['id']}'] = (data: r, baseTs: _parseTs(r['updated_at']));
    }
    final lines = <String, List<Map<String, Object?>>>{};
    for (final l in await db.query('sale_lines', orderBy: 'id')) {
      final m = Map<String, Object?>.from(l)
        ..remove('id')
        ..remove('sale_id');
      (lines[l['sale_id']! as String] ??= []).add(m);
    }
    for (final s in sales) {
      final id = s['id']! as String;
      out['sale/$id'] = (
        data: {'s': s, 'l': lines[id] ?? const []},
        baseTs: _parseTs(s['created_at']),
      );
    }
    final dir = await _photoDir();
    if (dir != null) {
      final seen = <String>{};
      final customers = await db.query('customers', columns: ['photo_path']);
      for (final r in [...items, ...customers]) {
        final stored = (r['photo_path'] as String?)?.trim() ?? '';
        if (stored.isEmpty) continue;
        final name = p.basename(stored);
        if (!seen.add(name)) continue;
        final f = File(p.join(dir, name));
        if (!f.existsSync()) continue;
        out['photo/$name'] = (data: 'size:${f.lengthSync()}', baseTs: 0);
      }
    }
    return out;
  }

  static ({String kind, String rid}) _split(String key) {
    final i = key.indexOf('/');
    return (kind: key.substring(0, i), rid: key.substring(i + 1));
  }

  /// Detect local edits since the last scan. Returns how many records got a
  /// new version. No-op until at least one device is paired.
  Future<int> scanLocal() async {
    final db = await _db();
    final peerCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_peers'),
    );
    if ((peerCount ?? 0) == 0 && !await _groupOn(db)) return 0;
    final me = await identity();
    final snap = await _snapshot(db);
    final baseline = await _meta(db, 'baseline') == null;
    final known = {
      for (final r in await db.query('sync_records'))
        '${r['kind']}/${r['rid']}': r,
    };
    var lseq = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COALESCE(MAX(lseq), 0) FROM sync_records'),
        ) ??
        0;
    final now = _now;
    final writes = <Map<String, Object?>>[];

    final keys = snap.keys.toList()
      ..sort((a, b) {
        final ka = _split(a).kind, kb = _split(b).kind;
        final c = syncKindRank(ka).compareTo(syncKindRank(kb));
        return c != 0 ? c : a.compareTo(b);
      });
    for (final key in keys) {
      final s = snap[key]!;
      final hash = recordHash(s.data);
      final prev = known[key];
      if (prev != null && prev['hash'] == hash && prev['deleted'] == 0) {
        continue;
      }
      final k = _split(key);
      final int ts;
      if (prev == null) {
        ts = baseline ? s.baseTs : now;
      } else {
        ts = nextEditTs(now, prev['ts']! as int);
      }
      writes.add({
        'kind': k.kind,
        'rid': k.rid,
        'hash': hash,
        'ts': ts,
        'origin': me.deviceId,
        'src': '',
        'deleted': 0,
        'lseq': ++lseq,
      });
    }

    final gone = [
      for (final e in known.entries)
        if (e.value['deleted'] == 0 &&
            e.value['kind'] != 'photo' &&
            !snap.containsKey(e.key))
          e,
    ];
    final businessLeft = snap.keys.where((k) => !k.startsWith('shop/')).length;
    // Safety: never broadcast a mass wipe caused by an unreadable/empty DB.
    final suspicious = businessLeft == 0 && gone.length > 20;
    if (!suspicious) {
      for (final e in gone) {
        writes.add({
          'kind': e.value['kind'],
          'rid': e.value['rid'],
          'hash': '',
          'ts': nextEditTs(now, e.value['ts']! as int),
          'origin': me.deviceId,
          'src': '',
          'deleted': 1,
          'lseq': ++lseq,
        });
      }
    }

    if (writes.isNotEmpty || baseline) {
      await db.transaction((txn) async {
        final b = txn.batch();
        for (final w in writes) {
          b.insert('sync_records', w,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await b.commit(noResult: true);
        if (baseline) await _setMeta(txn, 'baseline', '1');
      });
    }
    return writes.length;
  }

  // ------------------------------------------------------------------ apply

  Future<Map<String, Object?>> _filterCols(
    DatabaseExecutor db,
    String table,
    Object? data,
  ) async {
    if (data is! Map) return const {};
    final cols = await _cols(db, table);
    return {
      for (final e in data.entries)
        if (cols.contains('${e.key}')) '${e.key}': e.value,
    };
  }

  Future<void> _upsert(
    DatabaseExecutor db,
    String table,
    String id,
    Map<String, Object?> row,
  ) async {
    final clean = Map<String, Object?>.from(row)..['id'] = id;
    final n = await db.update(table, clean, where: 'id = ?', whereArgs: [id]);
    if (n == 0) await db.insert(table, clean);
  }

  Future<void> _applyOne(DatabaseExecutor db, SyncChange c) async {
    switch (c.kind) {
      case 'shop':
        if (c.deleted) return;
        final row = await _filterCols(db, 'shop_settings', c.data)
          ..remove('id');
        if (row.isNotEmpty) {
          await db.update('shop_settings', row, where: 'id = 1');
        }
      case 'cat':
        if (c.deleted) {
          await db.update('inventory_items', {'category_id': null},
              where: 'category_id = ?', whereArgs: [c.rid]);
          await db.delete('categories', where: 'id = ?', whereArgs: [c.rid]);
          return;
        }
        final row = await _filterCols(db, 'categories', c.data);
        final name = '${row['name'] ?? ''}';
        // Same name created separately on both devices: adopt the remote
        // id, re-point local items, drop the local duplicate.
        final dup = await db.query(
          'categories',
          where: 'LOWER(name) = ? AND id != ?',
          whereArgs: [name.toLowerCase(), c.rid],
        );
        for (final d in dup) {
          await db.update('inventory_items', {'category_id': c.rid},
              where: 'category_id = ?', whereArgs: [d['id']]);
          await db.delete('categories', where: 'id = ?', whereArgs: [d['id']]);
        }
        await _upsert(db, 'categories', c.rid, row);
      case 'cust':
        if (c.deleted) {
          await db.update('sales', {'customer_id': null},
              where: 'customer_id = ?', whereArgs: [c.rid]);
          await db.delete('customers', where: 'id = ?', whereArgs: [c.rid]);
          return;
        }
        await _upsert(db, 'customers', c.rid,
            await _filterCols(db, 'customers', c.data));
      case 'item':
        if (c.deleted) {
          await db.delete('inventory_items', where: 'id = ?', whereArgs: [c.rid]);
          return;
        }
        final row = await _filterCols(db, 'inventory_items', c.data);
        final photo = row['photo_path'];
        if (photo is String && photo.trim().isNotEmpty) {
          row['photo_path'] = p.join(_photoFolder, p.basename(photo.trim()));
        }
        await _upsert(db, 'inventory_items', c.rid, row);
      case 'sale':
        await db.delete('sale_lines', where: 'sale_id = ?', whereArgs: [c.rid]);
        if (c.deleted) {
          await db.delete('sales', where: 'id = ?', whereArgs: [c.rid]);
          return;
        }
        final d = c.data;
        if (d is! Map) return;
        await _upsert(db, 'sales', c.rid, await _filterCols(db, 'sales', d['s']));
        for (final l in (d['l'] as List? ?? const [])) {
          final line = await _filterCols(db, 'sale_lines', l)
            ..remove('id')
            ..['sale_id'] = c.rid;
          await db.insert('sale_lines', line);
        }
      case 'photo':
        if (c.deleted || c.data is! String) return;
        final dir = await _photoDir();
        if (dir == null) return;
        final name = p.basename(c.rid);
        final f = File(p.join(dir, name));
        if (!f.existsSync()) {
          await f.parent.create(recursive: true);
          await f.writeAsBytes(base64Decode(c.data! as String), flush: true);
        }
    }
  }

  /// Apply remote changes with last-write-wins. Returns how many won.
  ///
  /// [trashIf]: deletions it accepts are first copied to the trash (group
  /// mode: deletes by non-admin devices stay restorable for 30 days).
  Future<int> applyRemote(
    List<SyncChange> changes, {
    String src = '',
    bool Function(SyncChange c)? trashIf,
  }) async {
    if (changes.isEmpty) return 0;
    final db = await _db();
    final sorted = [...changes]
      ..sort((a, b) => syncKindRank(a.kind).compareTo(syncKindRank(b.kind)));
    var applied = 0;
    // Children may arrive before parents across messages; FK actions are
    // emulated in _applyOne, so enforcement can pause for this batch.
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        var lseq = Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COALESCE(MAX(lseq), 0) FROM sync_records',
              ),
            ) ??
            0;
        for (final c in sorted) {
          final local = await txn.query(
            'sync_records',
            where: 'kind = ? AND rid = ?',
            whereArgs: [c.kind, c.rid],
          );
          if (c.kind == 'photo' && local.isNotEmpty && !c.deleted) continue;
          if (local.isNotEmpty &&
              !remoteWins(
                localTs: local.first['ts']! as int,
                localOrigin: local.first['origin']! as String,
                remoteTs: c.ts,
                remoteOrigin: c.origin,
              )) {
            continue;
          }
          if (c.deleted &&
              trashIf != null &&
              _kTrashKinds.contains(c.kind) &&
              trashIf(c)) {
            await _toTrash(txn, c);
          }
          await _applyOne(txn, c);
          final snapHash = c.deleted ? '' : await _localHash(txn, c);
          await txn.insert(
            'sync_records',
            {
              'kind': c.kind,
              'rid': c.rid,
              'hash': snapHash,
              'ts': c.ts,
              'origin': c.origin,
              'src': src,
              'deleted': c.deleted ? 1 : 0,
              'lseq': ++lseq,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          applied++;
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
    return applied;
  }

  /// Hash of the record as it now reads locally (same shape as a scan).
  Future<String> _localHash(DatabaseExecutor db, SyncChange c) async {
    switch (c.kind) {
      case 'shop':
        final r = await db.query('shop_settings', where: 'id = 1');
        if (r.isEmpty) return '';
        return recordHash(Map<String, Object?>.from(r.first)..remove('id'));
      case 'photo':
        final dir = await _photoDir();
        if (dir == null) return '';
        final f = File(p.join(dir, p.basename(c.rid)));
        return f.existsSync() ? recordHash('size:${f.lengthSync()}') : '';
      case 'sale':
        final s = await db.query('sales', where: 'id = ?', whereArgs: [c.rid]);
        if (s.isEmpty) return '';
        final lines = [
          for (final l in await db.query('sale_lines',
              where: 'sale_id = ?', whereArgs: [c.rid], orderBy: 'id'))
            Map<String, Object?>.from(l)
              ..remove('id')
              ..remove('sale_id'),
        ];
        return recordHash({'s': s.first, 'l': lines});
      default:
        final table = const {
          'cat': 'categories',
          'cust': 'customers',
          'item': 'inventory_items',
        }[c.kind]!;
        final r = await db.query(table, where: 'id = ?', whereArgs: [c.rid]);
        return r.isEmpty ? '' : recordHash(r.first);
    }
  }

  // ------------------------------------------------------------ wire format

  static Future<SealedBlob> sealMessage(
    Map<String, Object?> msg, {
    required Uint8List key,
    required String pairId,
  }) {
    final clear = gzip.encode(utf8.encode(jsonEncode(msg)));
    return sealBytes(clear, key: key, aad: pairId);
  }

  static Future<Map<String, Object?>?> openMessage(
    SealedBlob blob, {
    required Uint8List key,
    required String pairId,
  }) async {
    final clear = await openBytes(blob, key: key, aad: pairId);
    final m = jsonDecode(utf8.decode(gzip.decode(clear)));
    return m is Map<String, Object?> ? m : null;
  }

  Future<Object?> _payloadFor(DatabaseExecutor db, String kind, String rid) async {
    switch (kind) {
      case 'shop':
        final r = await db.query('shop_settings', where: 'id = 1');
        return r.isEmpty ? null : (Map<String, Object?>.from(r.first)..remove('id'));
      case 'photo':
        final dir = await _photoDir();
        if (dir == null) return null;
        final f = File(p.join(dir, p.basename(rid)));
        return f.existsSync() ? base64Encode(await f.readAsBytes()) : null;
      case 'sale':
        final s = await db.query('sales', where: 'id = ?', whereArgs: [rid]);
        if (s.isEmpty) return null;
        final lines = [
          for (final l in await db.query('sale_lines',
              where: 'sale_id = ?', whereArgs: [rid], orderBy: 'id'))
            Map<String, Object?>.from(l)
              ..remove('id')
              ..remove('sale_id'),
        ];
        return {'s': s.first, 'l': lines};
      default:
        final table = const {
          'cat': 'categories',
          'cust': 'customers',
          'item': 'inventory_items',
        }[kind]!;
        final r = await db.query(table, where: 'id = ?', whereArgs: [rid]);
        return r.isEmpty ? null : r.first;
    }
  }

  // ------------------------------------------------------------------- run

  Future<void> _peerUpdate(
    DatabaseExecutor db,
    String peerId,
    Map<String, Object?> values,
  ) =>
      db.update('sync_peers', values, where: 'peer_id = ?', whereArgs: [peerId]);

  Future<int> _pushPeer(Database db, Map<String, Object?> peer) async {
    final me = await identity();
    final peerId = peer['peer_id']! as String;
    final key = unb64(peer['enc_key']! as String);
    final pairId = peer['pair_id']! as String;
    final auth = peer['auth']! as String;
    var pushed = 0;
    if (peer['status'] == 'removed') return 0;

    if (peer['hello_sent'] == 0) {
      final hello = await sealMessage(
        {'v': 1, 'f': me.deviceId, 'm': 'hello'},
        key: key,
        pairId: pairId,
      );
      await transport.push(
        pairId: pairId,
        auth: auth,
        sender: me.deviceId,
        blobs: [hello],
      );
      await _peerUpdate(db, peerId, {'hello_sent': 1});
    }
    if (peer['status'] != 'active') return 0;

    var cursor = peer['pushed_lseq']! as int;
    for (var round = 0; round < 20; round++) {
      final rows = await db.query(
        'sync_records',
        where: 'lseq > ? AND src != ?',
        whereArgs: [cursor, peerId],
        orderBy: 'lseq',
        limit: 400,
      );
      if (rows.isEmpty) break;
      final blobs = <SealedBlob>[];
      var blobBytes = 0;
      var batch = <Map<String, Object?>>[];
      var batchBytes = 0;
      var lastLseq = cursor;

      Future<void> flushMsg() async {
        if (batch.isEmpty) return;
        final b = await sealMessage(
          {'v': 1, 'f': me.deviceId, 'm': 'chg', 'c': batch},
          key: key,
          pairId: pairId,
        );
        blobs.add(b);
        blobBytes += b.ct.length;
        pushed += batch.length;
        batch = [];
        batchBytes = 0;
      }

      for (final r in rows) {
        final kind = r['kind']! as String;
        final rid = r['rid']! as String;
        final deleted = r['deleted'] == 1;
        final data = deleted ? null : await _payloadFor(db, kind, rid);
        lastLseq = r['lseq']! as int;
        if (!deleted && data == null) continue; // vanished; next scan tombstones
        final change = SyncChange(
          kind: kind,
          rid: rid,
          ts: r['ts']! as int,
          origin: r['origin']! as String,
          deleted: deleted,
          data: data,
        ).toJson();
        final size = jsonEncode(change).length;
        if (batch.isNotEmpty && batchBytes + size > _msgLimit) await flushMsg();
        batch.add(change);
        batchBytes += size;
        if (kind == 'photo') await flushMsg();
        if (blobBytes >= _requestLimit) {
          await flushMsg();
          break;
        }
      }
      await flushMsg();
      if (blobs.isNotEmpty) {
        await transport.push(
          pairId: pairId,
          auth: auth,
          sender: me.deviceId,
          blobs: blobs,
        );
      }
      // Everything up to the last processed record is on the relay now.
      cursor = lastLseq;
      await _peerUpdate(db, peerId, {'pushed_lseq': cursor});
      if (rows.length < 400 && blobBytes < _requestLimit) break;
    }
    return pushed;
  }

  Future<int> _pullPeer(Database db, Map<String, Object?> peer) async {
    final me = await identity();
    final peerId = peer['peer_id']! as String;
    final key = unb64(peer['enc_key']! as String);
    final pairId = peer['pair_id']! as String;
    final auth = peer['auth']! as String;
    var after = peer['pulled_seq']! as int;
    var status = peer['status']! as String;
    if (status == 'removed') return 0;
    var applied = 0;
    for (var page = 0; page < 20; page++) {
      final res = await transport.pull(
        pairId: pairId,
        auth: auth,
        device: me.deviceId,
        after: after,
      );
      for (final item in res.items) {
        Map<String, Object?>? msg;
        try {
          msg = await openMessage(item.blob, key: key, pairId: pairId);
        } catch (_) {
          msg = null; // not ours / corrupted — skip, never touch data
        }
        if (msg != null && msg['f'] == peerId) {
          if (status != 'active') {
            status = 'active';
            await _peerUpdate(db, peerId, {'status': 'active'});
          }
          if (msg['m'] == 'chg') {
            final changes = [
              for (final c in (msg['c'] as List? ?? const []))
                ?SyncChange.fromJson(c),
            ];
            applied += await applyRemote(
              changes,
              src: peerId,
              // In a group, old-style deletes are restorable too.
              trashIf: await _gState(db) == GroupState.active ? (_) => true : null,
            );
          } else if (msg['m'] == 'ginv') {
            await _onLegacyInvite(db, msg['i']);
          }
        }
        after = item.seq;
        await _peerUpdate(db, peerId, {'pulled_seq': after});
      }
      if (!res.more || res.items.isEmpty) break;
    }
    return applied;
  }

  /// SQLite `total_changes()` on the app's connection right after the last
  /// run (engine writes included), so a later run can tell whether anything
  /// else was written in between.
  int? _changesAfterRun;

  Future<int> _totalChanges(DatabaseExecutor db) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT total_changes()')) ?? -1;

  /// scan → pull+apply → scan → push, for every paired device.
  ///
  /// [skipUnchangedScan]: the frequent poll only pulls/pushes; the full local
  /// scan (reads + hashes every record) runs only if something was written
  /// since the last run or the pull applied changes.
  Future<SyncRunResult> syncOnce({bool skipUnchangedScan = false}) async {
    final db = await _db();
    if (!_offsetLoaded) {
      _offsetLoaded = true;
      _clockOffset = int.tryParse(await _meta(db, 'clock_offset') ?? '') ?? 0;
    }
    final peerRows = [
      for (final p in await db.query('sync_peers', orderBy: 'created_at'))
        if (p['status'] != 'removed') p,
    ];
    final groupOn = await _groupOn(db) && _groupTransport != null;
    if (peerRows.isEmpty && !groupOn) return const SyncRunResult();
    var applied = 0, pushed = 0;
    var offline = false;
    Object? error;
    final scan = !skipUnchangedScan ||
        _changesAfterRun == null ||
        await _totalChanges(db) != _changesAfterRun;
    if (scan) await scanLocal();
    for (final peer in peerRows) {
      final peerId = peer['peer_id']! as String;
      try {
        final got = await _pullPeer(db, peer);
        applied += got;
        if (scan || got > 0) await scanLocal();
        final fresh = (await db.query('sync_peers',
                where: 'peer_id = ?', whereArgs: [peerId]))
            .firstOrNull;
        if (fresh == null) continue;
        pushed += await _pushPeer(db, fresh);
        await _maybeInviteLegacy(db, fresh);
        await _peerUpdate(db, peerId, {
          'last_sync_at': _now,
          'last_error': null,
        });
      } on SyncOfflineException {
        offline = true;
      } catch (e) {
        if (e is SyncServerException && e.status == 410) {
          // The other device unpaired: stop syncing, keep all local data.
          await _peerUpdate(db, peerId, {'status': 'removed', 'last_error': null});
          continue;
        }
        error = e;
        final msg = '$e';
        await _peerUpdate(db, peerId, {
          'last_error': msg.length > 200 ? msg.substring(0, 200) : msg,
        });
      }
    }
    if (groupOn) {
      final before = _clockOffset;
      try {
        final got = await _groupPullPhase(db);
        applied += got;
        if (scan || got > 0) await scanLocal();
        pushed += await _groupPushPhase(db);
      } on SyncOfflineException {
        offline = true;
      } catch (e) {
        final st = await _gState(db);
        if (e is SyncServerException && e.status == 410) {
          // An admin removed this device: stop, keep all local data.
          await _becomeRemoved(db);
        } else if (e is SyncServerException &&
            e.status == 401 &&
            st == GroupState.joining) {
          // The admin declined the request.
          await _clearGroupLocal(db);
          await _setMeta(db, 'g_declined', '1');
        } else {
          error = e;
        }
      }
      if (before != _clockOffset) {
        await _setMeta(db, 'clock_offset', '$_clockOffset');
      }
    }
    _changesAfterRun = await _totalChanges(db);
    return SyncRunResult(
      applied: applied,
      pushed: pushed,
      offline: offline,
      error: error,
    );
  }
}
