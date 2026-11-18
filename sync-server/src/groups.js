// v2: admin-managed device groups (one encrypted mailbox per shop).
// The relay only sees random ids, roles, token hashes, public keys and
// AES-GCM ciphertext. It enforces WHO may write (active devices) and WHO may
// manage devices (admins); the clients additionally verify admin-signed
// member lists and per-message Ed25519 signatures end to end.
const PART = 400_000;
const MAX_BODY = 40 * 1024 * 1024;
const MAX_PULL_BYTES = 6 * 1024 * 1024;
export const GROUP_RETAIN_MS = 60 * 24 * 3600 * 1000; // unread ciphertext
const MAX_INVITE_MS = 30 * 24 * 3600 * 1000;
const PENDING_MS = 7 * 24 * 3600 * 1000;
const REVOKED_KEEP_MS = 180 * 24 * 3600 * 1000;

const ID_RE = /^[A-Za-z0-9_-]{16,128}$/;
const KEY_RE = /^[A-Za-z0-9+/=]{40,48}$/; // base64 32-byte public key

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
const fail = (error, status) => json({ error }, status);

async function sha256Hex(s) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function timingSafeEq(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

const bearer = (request) => {
  const h = request.headers.get('authorization') || '';
  return h.startsWith('Bearer ') ? h.slice(7) : '';
};

async function body(request) {
  const len = Number(request.headers.get('content-length') || 0);
  if (len > MAX_BODY) return null;
  return request.json().catch(() => null);
}

/** The calling device's row, or an error response. */
async function caller(env, g, request) {
  const dev = request.headers.get('x-device') || '';
  const token = bearer(request);
  if (!ID_RE.test(dev) || token.length < 32) return { res: fail('unauthorized', 401) };
  const row = await env.DB.prepare(
    'SELECT * FROM group_devices WHERE group_id = ? AND device_id = ?',
  ).bind(g, dev).first();
  if (!row || !timingSafeEq(row.token_hash, await sha256Hex(token))) {
    return { res: fail('unauthorized', 401) };
  }
  // Removed by an admin: the device learns it (410) and stops.
  if (row.status === 'revoked') return { res: fail('revoked', 410) };
  return { row };
}

async function admin(env, g, request) {
  const c = await caller(env, g, request);
  if (c.res) return c;
  if (c.row.status !== 'active' || c.row.role !== 'admin') return { res: fail('not_admin', 403) };
  return c;
}

const maxSeq = async (env, g) =>
  (await env.DB.prepare('SELECT COALESCE(MAX(seq), 0) AS s FROM group_changes WHERE group_id = ?')
    .bind(g).first()).s;

const otherAdmins = async (env, g, device) =>
  (await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM group_devices WHERE group_id = ? AND device_id != ? AND status = 'active' AND role = 'admin'",
  ).bind(g, device).first()).n;

async function create(env, g, request) {
  const dev = request.headers.get('x-device') || '';
  const token = bearer(request);
  const b = await body(request);
  if (!ID_RE.test(dev) || token.length < 32 || !b || !KEY_RE.test(b.x_pub || '')) {
    return fail('bad_request', 400);
  }
  const now = Date.now();
  const res = await env.DB.prepare(
    'INSERT OR IGNORE INTO groups (group_id, created_at) VALUES (?, ?)',
  ).bind(g, now).run();
  if (!res.meta || res.meta.changes !== 1) return fail('exists', 409);
  await env.DB.prepare(
    "INSERT INTO group_devices (group_id, device_id, token_hash, role, status, x_pub, created_at, last_seen) VALUES (?, ?, ?, 'admin', 'active', ?, ?, ?)",
  ).bind(g, dev, await sha256Hex(token), b.x_pub, now, now).run();
  return json({ ok: true, now });
}

async function invite(env, g, request) {
  const a = await admin(env, g, request);
  if (a.res) return a.res;
  const b = await body(request);
  const now = Date.now();
  if (!b || !/^[0-9a-f]{64}$/.test(b.secret_hash || '') || typeof b.expires_at !== 'number') {
    return fail('bad_request', 400);
  }
  const exp = Math.min(b.expires_at, now + MAX_INVITE_MS);
  await env.DB.prepare(
    'INSERT OR REPLACE INTO group_invites (secret_hash, group_id, created_by, expires_at) VALUES (?, ?, ?, ?)',
  ).bind(b.secret_hash, g, a.row.device_id, exp).run();
  return json({ ok: true, expires_at: exp, now });
}

async function join(env, g, request) {
  const token = bearer(request);
  const b = await body(request);
  if (!b || token.length < 32 || !ID_RE.test(b.device || '') || typeof b.secret !== 'string' ||
      b.secret.length < 16 || !KEY_RE.test(b.x_pub || '') || typeof b.iv !== 'string' ||
      typeof b.ct !== 'string' || b.ct.length > 8000) {
    return fail('bad_request', 400);
  }
  const now = Date.now();
  const hash = await sha256Hex(b.secret);
  // One-time: the first join consumes the invite.
  const used = await env.DB.prepare(
    'UPDATE group_invites SET used_at = ? WHERE secret_hash = ? AND group_id = ? AND used_at IS NULL AND expires_at > ? RETURNING created_by',
  ).bind(now, hash, g, now).first();
  if (!used) return fail('invite_invalid', 403);
  const existing = await env.DB.prepare(
    'SELECT status FROM group_devices WHERE group_id = ? AND device_id = ?',
  ).bind(g, b.device).first();
  if (existing && existing.status === 'active') return fail('already_member', 409);
  await env.DB.prepare(
    "INSERT OR REPLACE INTO group_devices (group_id, device_id, token_hash, role, status, x_pub, join_iv, join_ct, created_at) VALUES (?, ?, ?, 'member', 'pending', ?, ?, ?, ?)",
  ).bind(g, b.device, await sha256Hex(token), b.x_pub, b.iv, b.ct, now).run();
  return json({ ok: true, now });
}

async function joins(env, g, request) {
  const a = await admin(env, g, request);
  if (a.res) return a.res;
  const { results } = await env.DB.prepare(
    "SELECT device_id, x_pub, join_iv, join_ct, created_at FROM group_devices WHERE group_id = ? AND status = 'pending' ORDER BY created_at",
  ).bind(g).all();
  return json({
    ok: true,
    now: Date.now(),
    items: results.map((r) => ({
      device: r.device_id, x_pub: r.x_pub, iv: r.join_iv, ct: r.join_ct, at: r.created_at,
    })),
  });
}

async function target(env, g, d) {
  return env.DB.prepare('SELECT * FROM group_devices WHERE group_id = ? AND device_id = ?')
    .bind(g, d).first();
}

async function approve(env, g, d, request) {
  const a = await admin(env, g, request);
  if (a.res) return a.res;
  const b = (await body(request)) || {};
  const role = b.role === 'admin' ? 'admin' : 'member';
  const t = await target(env, g, d);
  if (!t || t.status !== 'pending') return fail('not_pending', 409);
  const start = await maxSeq(env, g);
  await env.DB.prepare(
    "UPDATE group_devices SET status = 'active', role = ?, start_seq = ?, cursor = ?, join_iv = NULL, join_ct = NULL, last_seen = ? WHERE group_id = ? AND device_id = ?",
  ).bind(role, start, start, Date.now(), g, d).run();
  return json({ ok: true, start_seq: start });
}

async function reject(env, g, d, request) {
  const a = await admin(env, g, request);
  if (a.res) return a.res;
  await env.DB.prepare(
    "DELETE FROM group_devices WHERE group_id = ? AND device_id = ? AND status = 'pending'",
  ).bind(g, d).run();
  return json({ ok: true });
}

async function revokeDevice(env, g, d) {
  const t = await target(env, g, d);
  if (!t || t.status === 'revoked') return json({ ok: true, seq: await maxSeq(env, g) });
  if (t.status === 'active' && t.role === 'admin' && (await otherAdmins(env, g, d)) === 0) {
    return fail('last_admin', 409);
  }
  await env.DB.prepare(
    "UPDATE group_devices SET status = 'revoked', revoked_at = ? WHERE group_id = ? AND device_id = ?",
  ).bind(Date.now(), g, d).run();
  // Everything up to here was written while the device was a member.
  return json({ ok: true, seq: await maxSeq(env, g) });
}

async function revoke(env, g, d, request) {
  const a = await admin(env, g, request);
  if (a.res) return a.res;
  return revokeDevice(env, g, d);
}

async function leave(env, g, request) {
  const c = await caller(env, g, request);
  if (c.res) return c.res.status === 410 ? json({ ok: true }) : c.res;
  const me = c.row;
  if (me.status === 'active' && me.role === 'admin' && (await otherAdmins(env, g, me.device_id)) === 0) {
    const others = (await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM group_devices WHERE group_id = ? AND device_id != ? AND status = 'active'",
    ).bind(g, me.device_id).first()).n;
    if (others > 0) return fail('last_admin', 409);
  }
  await env.DB.prepare(
    "UPDATE group_devices SET status = 'revoked', revoked_at = ? WHERE group_id = ? AND device_id = ?",
  ).bind(Date.now(), g, me.device_id).run();
  return json({ ok: true });
}

async function setRole(env, g, d, request) {
  const a = await admin(env, g, request);
  if (a.res) return a.res;
  const b = await body(request);
  if (!b || (b.role !== 'admin' && b.role !== 'member')) return fail('bad_request', 400);
  const t = await target(env, g, d);
  if (!t || t.status !== 'active') return fail('not_member', 409);
  if (b.role === 'member' && t.role === 'admin' && (await otherAdmins(env, g, d)) === 0) {
    return fail('last_admin', 409);
  }
  await env.DB.prepare('UPDATE group_devices SET role = ? WHERE group_id = ? AND device_id = ?')
    .bind(b.role, g, d).run();
  return json({ ok: true });
}

async function push(env, g, request) {
  const c = await caller(env, g, request);
  if (c.res) return c.res;
  if (c.row.status !== 'active') return fail('not_active', 403);
  const b = await body(request);
  if (!b || !Array.isArray(b.items)) return fail('bad_request', 400);
  const now = Date.now();
  const seqs = [];
  for (const it of b.items) {
    const epoch = Number.isInteger(it.epoch) ? it.epoch : -1;
    const to = it.to == null ? null : it.to;
    if (typeof it.iv !== 'string' || typeof it.ct !== 'string' || !it.ct || epoch < 0 ||
        (to !== null && !ID_RE.test(to))) {
      return fail('bad_item', 400);
    }
    const parts = Math.ceil(it.ct.length / PART);
    const res = await env.DB.prepare(
      'INSERT INTO group_changes (group_id, sender, recipient, epoch, iv, parts, size, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING seq',
    ).bind(g, c.row.device_id, to, epoch, it.iv, parts, it.ct.length, now).first();
    const stmts = [];
    for (let i = 0; i < parts; i++) {
      stmts.push(env.DB.prepare('INSERT INTO group_change_parts (seq, idx, data) VALUES (?, ?, ?)')
        .bind(res.seq, i, it.ct.slice(i * PART, (i + 1) * PART)));
    }
    await env.DB.batch(stmts);
    seqs.push(res.seq);
  }
  return json({ ok: true, seqs, now });
}

async function pull(env, g, request, url) {
  const c = await caller(env, g, request);
  if (c.res) return c.res;
  const me = c.row;
  const now = Date.now();
  if (me.status !== 'active') {
    return json({ ok: true, status: me.status, role: me.role, items: [], more: false, gap: false, now });
  }
  const after = Math.max(0, Number(url.searchParams.get('after') || 0) || 0);
  const from = Math.max(after, me.start_seq);
  const grp = await env.DB.prepare('SELECT purged_upto FROM groups WHERE group_id = ?').bind(g).first();
  // Rows this device never fetched were already deleted: it must resync.
  const gap = !!grp && grp.purged_upto > from;
  await env.DB.prepare(
    'UPDATE group_devices SET cursor = MAX(cursor, ?), last_seen = ? WHERE group_id = ? AND device_id = ?',
  ).bind(from, now, g, me.device_id).run();
  const { results } = await env.DB.prepare(
    'SELECT seq, sender, recipient, epoch, iv, parts, size FROM group_changes WHERE group_id = ? AND seq > ? AND sender != ? AND (recipient IS NULL OR recipient = ?) ORDER BY seq LIMIT 200',
  ).bind(g, from, me.device_id, me.device_id).all();
  const items = [];
  let bytes = 0;
  for (const r of results) {
    if (items.length && bytes + r.size > MAX_PULL_BYTES) break;
    const { results: parts } = await env.DB.prepare(
      'SELECT data FROM group_change_parts WHERE seq = ? ORDER BY idx',
    ).bind(r.seq).all();
    if (parts.length !== r.parts) continue;
    items.push({
      seq: r.seq, sender: r.sender, to: r.recipient, epoch: r.epoch, iv: r.iv,
      ct: parts.map((p) => p.data).join(''),
    });
    bytes += r.size;
  }
  const more = items.length < results.length || results.length === 200;
  return json({ ok: true, status: me.status, role: me.role, items, more, gap, now });
}

/** Routes under /v2/groups/:g. Returns null when the path is not v2. */
export async function handleGroups(request, env, url, path) {
  const m = path.match(/^\/v2\/groups\/([^/]+)(?:\/(changes|invites|join|joins|leave|devices\/([^/]+)\/(approve|reject|revoke|role)))?$/);
  if (!m) return null;
  const g = m[1];
  if (!ID_RE.test(g)) return fail('not_found', 404);
  const action = m[2] || '';
  const d = m[3];
  if (d !== undefined && !ID_RE.test(d)) return fail('not_found', 404);
  const method = request.method;
  if (action === '' && method === 'POST') return create(env, g, request);
  if (action === 'invites' && method === 'POST') return invite(env, g, request);
  if (action === 'join' && method === 'POST') return join(env, g, request);
  if (action === 'joins' && method === 'GET') return joins(env, g, request);
  if (action === 'leave' && method === 'POST') return leave(env, g, request);
  if (action === 'changes' && method === 'POST') return push(env, g, request);
  if (action === 'changes' && method === 'GET') return pull(env, g, request, url);
  if (d !== undefined && method === 'POST') {
    const op = m[4];
    if (op === 'approve') return approve(env, g, d, request);
    if (op === 'reject') return reject(env, g, d, request);
    if (op === 'revoke') return revoke(env, g, d, request);
    if (op === 'role') return setRole(env, g, d, request);
  }
  return fail('method_not_allowed', 405);
}

/** Daily cleanup: read-by-everyone or 60-day-old ciphertext, stale invites. */
export async function purgeGroups(env, now = Date.now()) {
  const cutoff = now - GROUP_RETAIN_MS;
  // A row is done once every active device's cursor has passed it.
  const done = `(created_at < ?1 OR seq <= COALESCE((SELECT MIN(cursor) FROM group_devices d
      WHERE d.group_id = group_changes.group_id AND d.status = 'active'), 0))`;
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE groups SET purged_upto = MAX(purged_upto, COALESCE((SELECT MAX(seq) FROM group_changes
         WHERE group_changes.group_id = groups.group_id AND created_at < ?1), 0))`,
    ).bind(cutoff),
    env.DB.prepare(`DELETE FROM group_change_parts WHERE seq IN (SELECT seq FROM group_changes WHERE ${done})`).bind(cutoff),
    env.DB.prepare(`DELETE FROM group_changes WHERE ${done}`).bind(cutoff),
    env.DB.prepare('DELETE FROM group_invites WHERE expires_at < ?1 OR used_at IS NOT NULL').bind(now - 24 * 3600 * 1000),
    env.DB.prepare("DELETE FROM group_devices WHERE status = 'pending' AND created_at < ?1").bind(now - PENDING_MS),
    env.DB.prepare("DELETE FROM group_devices WHERE status = 'revoked' AND revoked_at < ?1").bind(now - REVOKED_KEEP_MS),
  ]);
}
