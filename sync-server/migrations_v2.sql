-- v2: admin-managed device groups. Apply once to the existing D1 database:
--   npx wrangler d1 execute inventory-sync --remote --file=migrations_v2.sql
-- Same zero-knowledge rule as v1: random ids, roles, token hashes, public
-- keys and AES-GCM ciphertext only. No shop data, no device names.
CREATE TABLE IF NOT EXISTS groups (
  group_id    TEXT PRIMARY KEY,          -- random, chosen by the first admin
  created_at  INTEGER NOT NULL,
  purged_upto INTEGER NOT NULL DEFAULT 0 -- highest seq already deleted
);
CREATE TABLE IF NOT EXISTS group_devices (
  group_id   TEXT NOT NULL,
  device_id  TEXT NOT NULL,              -- random device UUID
  token_hash TEXT NOT NULL,              -- SHA-256 of the device's bearer token
  role       TEXT NOT NULL DEFAULT 'member',  -- admin | member
  status     TEXT NOT NULL DEFAULT 'pending', -- pending | active | revoked
  x_pub      TEXT,                       -- X25519 public key (for the join request)
  join_iv    TEXT,                       -- join request, sealed to the admin
  join_ct    TEXT,
  start_seq  INTEGER NOT NULL DEFAULT 0, -- mailbox position when approved
  cursor     INTEGER NOT NULL DEFAULT 0, -- everything <= cursor was pulled
  created_at INTEGER NOT NULL,
  last_seen  INTEGER,
  revoked_at INTEGER,
  PRIMARY KEY (group_id, device_id)
);
CREATE TABLE IF NOT EXISTS group_invites (
  secret_hash TEXT PRIMARY KEY,          -- SHA-256 of the one-time QR secret
  group_id    TEXT NOT NULL,
  created_by  TEXT NOT NULL,
  expires_at  INTEGER NOT NULL,
  used_at     INTEGER
);
CREATE TABLE IF NOT EXISTS group_changes (
  seq        INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id   TEXT NOT NULL,
  sender     TEXT NOT NULL,
  recipient  TEXT,                       -- NULL = whole group
  epoch      INTEGER NOT NULL,           -- group key generation (0 = direct)
  iv         TEXT NOT NULL,
  parts      INTEGER NOT NULL,
  size       INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS group_changes_g_seq ON group_changes(group_id, seq);
CREATE TABLE IF NOT EXISTS group_change_parts (
  seq  INTEGER NOT NULL,
  idx  INTEGER NOT NULL,
  data TEXT NOT NULL,
  PRIMARY KEY (seq, idx)
);
