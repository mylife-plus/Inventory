import 'package:sqflite/sqflite.dart';

/// Local-only sync tables (never exported in backups, never sent anywhere).
/// Idempotent — safe on every open for new and old installs.
Future<void> ensureSyncTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_meta (
      k TEXT PRIMARY KEY,
      v TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_peers (
      peer_id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      public_key TEXT NOT NULL,
      peer_nonce TEXT NOT NULL,
      my_nonce TEXT NOT NULL,
      enc_key TEXT NOT NULL,
      pair_id TEXT NOT NULL,
      auth TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at INTEGER NOT NULL,
      last_sync_at INTEGER,
      pushed_lseq INTEGER NOT NULL DEFAULT 0,
      pulled_seq INTEGER NOT NULL DEFAULT 0,
      hello_sent INTEGER NOT NULL DEFAULT 0,
      last_error TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_records (
      kind TEXT NOT NULL,
      rid TEXT NOT NULL,
      hash TEXT NOT NULL,
      ts INTEGER NOT NULL,
      origin TEXT NOT NULL,
      src TEXT NOT NULL DEFAULT '',
      deleted INTEGER NOT NULL DEFAULT 0,
      lseq INTEGER NOT NULL,
      PRIMARY KEY (kind, rid)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS sync_records_lseq ON sync_records(lseq)',
  );
  // v2 groups: key per generation (old ones kept to read older messages).
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_group_keys (
      epoch INTEGER PRIMARY KEY,
      k TEXT NOT NULL
    )
  ''');
  // Join requests waiting for this admin's Approve.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_joins (
      device_id TEXT PRIMARY KEY,
      public_key TEXT NOT NULL,
      sign_key TEXT NOT NULL,
      legacy_name TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  // Deletions by non-admin devices, restorable by admins for 30 days.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_trash (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      rid TEXT NOT NULL,
      title TEXT NOT NULL,
      data TEXT NOT NULL,
      by_device TEXT NOT NULL,
      deleted_at INTEGER NOT NULL
    )
  ''');
  // Remote edits stamped too far in the future (wrong clock): applied
  // once their time is reached instead of beating every later edit.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_deferred (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts INTEGER NOT NULL,
      src TEXT NOT NULL,
      change TEXT NOT NULL
    )
  ''');
}

/// Erase Data / Reset App: forget identity, pairing keys and paired devices.
Future<void> wipeSyncTables(DatabaseExecutor db) async {
  for (final t in [
    'sync_records',
    'sync_peers',
    'sync_meta',
    'sync_group_keys',
    'sync_joins',
    'sync_trash',
    'sync_deferred',
  ]) {
    try {
      await db.delete(t);
    } catch (_) {
      // Table missing (never opened with sync) — nothing to clear.
    }
  }
}
