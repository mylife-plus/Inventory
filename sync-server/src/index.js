// Inventory App — end-to-end encrypted sync relay (Cloudflare Worker + D1).
// The server never sees plaintext: clients send AES-GCM ciphertext only.
import { handleGroups, purgeGroups } from './groups.js';
const PART = 400_000;               // base64 chars per D1 row (< 2 MB row cap)
const MAX_BODY = 40 * 1024 * 1024;  // per push request
const MAX_PULL_BYTES = 6 * 1024 * 1024;
const RETAIN_MS = 7 * 24 * 3600 * 1000;

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });

const ID_RE = /^[A-Za-z0-9_-]{16,128}$/;

async function sha256Hex(s) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function timingSafeEq(a, b) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

// First request for a pair registers its auth hash; later ones must match.
async function authorize(env, pairId, request, { register }) {
  const h = request.headers.get('authorization') || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';
  if (token.length < 32) return 'unauthorized';
  const hash = await sha256Hex(token);
  const row = await env.DB.prepare('SELECT auth_hash, closed_at FROM pairs WHERE pair_id = ?')
    .bind(pairId).first();
  if (!row) {
    if (!register) return 'unknown_pair';
    await env.DB.prepare(
      'INSERT OR IGNORE INTO pairs (pair_id, auth_hash, created_at) VALUES (?, ?, ?)',
    ).bind(pairId, hash, Date.now()).run();
    const again = await env.DB.prepare('SELECT auth_hash FROM pairs WHERE pair_id = ?')
      .bind(pairId).first();
    return again && timingSafeEq(again.auth_hash, hash) ? null : 'unauthorized';
  }
  if (!timingSafeEq(row.auth_hash, hash)) return 'unauthorized';
  // Unpaired by one side: the other side learns it (410) instead of
  // silently re-registering and pushing into a dead mailbox.
  return row.closed_at ? 'pair_closed' : null;
}

const authFail = (err) =>
  err === 'pair_closed' ? json({ error: err }, 410) : json({ error: err }, 401);

async function push(env, pairId, request) {
  const len = Number(request.headers.get('content-length') || 0);
  if (len > MAX_BODY) return json({ error: 'too_large' }, 413);
  const body = await request.json().catch(() => null);
  if (!body || !ID_RE.test(body.sender || '') || !Array.isArray(body.items)) {
    return json({ error: 'bad_request' }, 400);
  }
  const now = Date.now();
  const seqs = [];
  for (const it of body.items) {
    if (typeof it.iv !== 'string' || typeof it.ct !== 'string' || !it.ct) {
      return json({ error: 'bad_item' }, 400);
    }
    const parts = Math.ceil(it.ct.length / PART);
    const res = await env.DB.prepare(
      'INSERT INTO changes (pair_id, sender, iv, parts, size, created_at) VALUES (?, ?, ?, ?, ?, ?) RETURNING seq',
    ).bind(pairId, body.sender, it.iv, parts, it.ct.length, now).first();
    const seq = res.seq;
    const stmts = [];
    for (let i = 0; i < parts; i++) {
      stmts.push(env.DB.prepare('INSERT INTO change_parts (seq, idx, data) VALUES (?, ?, ?)')
        .bind(seq, i, it.ct.slice(i * PART, (i + 1) * PART)));
    }
    await env.DB.batch(stmts);
    seqs.push(seq);
  }
  return json({ ok: true, seqs });
}

async function pull(env, pairId, url) {
  const device = url.searchParams.get('device') || '';
  const after = Number(url.searchParams.get('after') || 0) || 0;
  if (!ID_RE.test(device)) return json({ error: 'bad_request' }, 400);
  // The reader has everything up to `after` from the other side: drop it.
  if (after > 0) {
    await env.DB.batch([
      env.DB.prepare(
        'DELETE FROM change_parts WHERE seq IN (SELECT seq FROM changes WHERE pair_id = ? AND sender != ? AND seq <= ?)',
      ).bind(pairId, device, after),
      env.DB.prepare('DELETE FROM changes WHERE pair_id = ? AND sender != ? AND seq <= ?')
        .bind(pairId, device, after),
    ]);
  }
  const { results } = await env.DB.prepare(
    'SELECT seq, iv, parts, size FROM changes WHERE pair_id = ? AND sender != ? AND seq > ? ORDER BY seq LIMIT 200',
  ).bind(pairId, device, after).all();
  const items = [];
  let bytes = 0;
  for (const r of results) {
    if (items.length && bytes + r.size > MAX_PULL_BYTES) break;
    const { results: parts } = await env.DB.prepare(
      'SELECT data FROM change_parts WHERE seq = ? ORDER BY idx',
    ).bind(r.seq).all();
    if (parts.length !== r.parts) continue; // incomplete write — skip
    items.push({ seq: r.seq, iv: r.iv, ct: parts.map((p) => p.data).join('') });
    bytes += r.size;
  }
  const more = items.length < results.length || results.length === 200;
  return json({ ok: true, items, more });
}

async function dropPair(env, pairId) {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM change_parts WHERE seq IN (SELECT seq FROM changes WHERE pair_id = ?)').bind(pairId),
    env.DB.prepare('DELETE FROM changes WHERE pair_id = ?').bind(pairId),
    // Keep only a closed marker (opaque id + hash) so the peer sees 410.
    env.DB.prepare('UPDATE pairs SET closed_at = ? WHERE pair_id = ?').bind(Date.now(), pairId),
  ]);
  return json({ ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');
    if (path === '/v1/health' || path === '') {
      return json({ ok: true, service: 'inventory-sync', v: 2 });
    }
    if (path.startsWith('/v2/')) {
      try {
        return (await handleGroups(request, env, url, path)) || json({ error: 'not_found' }, 404);
      } catch (e) {
        return json({ error: 'server_error' }, 500);
      }
    }
    const m = path.match(/^\/v1\/pairs\/([^/]+)(\/changes)?$/);
    if (!m || !ID_RE.test(m[1])) return json({ error: 'not_found' }, 404);
    const pairId = m[1];
    const isChanges = !!m[2];
    try {
      if (isChanges && request.method === 'POST') {
        const err = await authorize(env, pairId, request, { register: true });
        if (err) return authFail(err);
        return await push(env, pairId, request);
      }
      if (isChanges && request.method === 'GET') {
        const err = await authorize(env, pairId, request, { register: true });
        if (err) return authFail(err);
        return await pull(env, pairId, url);
      }
      if (!isChanges && request.method === 'DELETE') {
        const err = await authorize(env, pairId, request, { register: false });
        if (err === 'unknown_pair' || err === 'pair_closed') return json({ ok: true });
        if (err) return json({ error: err }, 401);
        return await dropPair(env, pairId);
      }
    } catch (e) {
      return json({ error: 'server_error' }, 500);
    }
    return json({ error: 'method_not_allowed' }, 405);
  },

  // Daily: drop ciphertext nobody fetched for 7 days.
  async scheduled(_event, env) {
    const cutoff = Date.now() - RETAIN_MS;
    await env.DB.batch([
      env.DB.prepare('DELETE FROM change_parts WHERE seq IN (SELECT seq FROM changes WHERE created_at < ?)').bind(cutoff),
      env.DB.prepare('DELETE FROM changes WHERE created_at < ?').bind(cutoff),
      env.DB.prepare('DELETE FROM pairs WHERE closed_at IS NOT NULL AND closed_at < ?').bind(cutoff),
    ]);
    await purgeGroups(env);
  },
};
