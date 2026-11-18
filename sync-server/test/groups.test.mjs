// Server rules for v2 groups, against a LOCAL worker only:
//   npx wrangler d1 execute inventory-sync --local --persist-to /tmp/wr-test --file=schema.sql
//   npx wrangler dev --local --persist-to /tmp/wr-test --test-scheduled
//   BASE=http://127.0.0.1:8787 node --test test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';

const BASE = process.env.BASE || 'http://127.0.0.1:8787';
const rid = () => crypto.randomBytes(18).toString('base64url');
const pub = () => crypto.randomBytes(32).toString('base64');
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

function dev() { return { id: rid(), token: rid() + rid(), x: pub() }; }
async function call(method, path, d, body) {
  const headers = { 'content-type': 'application/json' };
  if (d) { headers.authorization = `Bearer ${d.token}`; headers['x-device'] = d.id; }
  const r = await fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
}
async function group() {
  const g = rid(); const a = dev();
  const r = await call('POST', `/v2/groups/${g}`, a, { x_pub: a.x });
  assert.equal(r.status, 200);
  return { g, a };
}
async function invite(g, a, ttl = 600000) {
  const secret = rid();
  const r = await call('POST', `/v2/groups/${g}/invites`, a, { secret_hash: sha(secret), expires_at: Date.now() + ttl });
  assert.equal(r.status, 200);
  return secret;
}
async function joinAndApprove(g, a, role = 'member') {
  const d = dev(); const secret = await invite(g, a);
  let r = await call('POST', `/v2/groups/${g}/join`, d, { secret, device: d.id, x_pub: d.x, iv: 'aa', ct: 'bb' });
  assert.equal(r.status, 200);
  r = await call('POST', `/v2/groups/${g}/devices/${d.id}/approve`, a, { role });
  assert.equal(r.status, 200);
  return d;
}
const push = (g, d, items) => call('POST', `/v2/groups/${g}/changes`, d, { items });
const pull = (g, d, after = 0) => call('GET', `/v2/groups/${g}/changes?after=${after}`, d);

test('create: second create of the same id is refused', async () => {
  const { g } = await group();
  const r = await call('POST', `/v2/groups/${g}`, dev(), { x_pub: pub() });
  assert.equal(r.status, 409);
});

test('join needs a valid one-time invite; pending devices cannot read or write', async () => {
  const { g, a } = await group();
  const d = dev();
  let r = await call('POST', `/v2/groups/${g}/join`, d, { secret: rid(), device: d.id, x_pub: d.x, iv: 'a', ct: 'b' });
  assert.equal(r.status, 403, 'unknown invite');
  const secret = await invite(g, a);
  r = await call('POST', `/v2/groups/${g}/join`, d, { secret, device: d.id, x_pub: d.x, iv: 'a', ct: 'b' });
  assert.equal(r.status, 200);
  const e = dev();
  r = await call('POST', `/v2/groups/${g}/join`, e, { secret, device: e.id, x_pub: e.x, iv: 'a', ct: 'b' });
  assert.equal(r.status, 403, 'invite is single-use');
  r = await pull(g, d);
  assert.equal(r.status, 200); assert.equal(r.body.status, 'pending'); assert.equal(r.body.items.length, 0);
  r = await push(g, d, [{ iv: 'x', ct: 'y', epoch: 1 }]);
  assert.equal(r.status, 403);
  r = await call('GET', `/v2/groups/${g}/joins`, a);
  assert.equal(r.body.items.length, 1); assert.equal(r.body.items[0].device, d.id); assert.equal(r.body.items[0].x_pub, d.x);
});

test('expired invite is refused', async () => {
  const { g, a } = await group();
  const secret = await invite(g, a, -1000);
  const d = dev();
  const r = await call('POST', `/v2/groups/${g}/join`, d, { secret, device: d.id, x_pub: d.x, iv: 'a', ct: 'b' });
  assert.equal(r.status, 403);
});

test('only admins manage devices', async () => {
  const { g, a } = await group();
  const m = await joinAndApprove(g, a);
  for (const [method, path, body] of [
    ['POST', `/v2/groups/${g}/invites`, { secret_hash: sha('x'), expires_at: Date.now() + 1000 }],
    ['GET', `/v2/groups/${g}/joins`],
    ['POST', `/v2/groups/${g}/devices/${a.id}/revoke`, {}],
    ['POST', `/v2/groups/${g}/devices/${a.id}/role`, { role: 'member' }],
  ]) {
    const r = await call(method, path, m, body);
    assert.equal(r.status, 403, `${method} ${path}`);
  }
  const wrongToken = { ...a, token: rid() + rid() };
  assert.equal((await pull(g, wrongToken)).status, 401);
});

test('mailbox: new device starts at its approval point; direct items only reach the recipient', async () => {
  const { g, a } = await group();
  const old = await push(g, a, [{ iv: 'i0', ct: 'before', epoch: 1 }]);
  assert.equal(old.status, 200);
  const b = await joinAndApprove(g, a);
  const c = await joinAndApprove(g, a);
  await push(g, a, [{ iv: 'i1', ct: 'all', epoch: 1 }, { iv: 'i2', ct: 'forB', epoch: 0, to: b.id }]);
  const rb = await pull(g, b);
  assert.deepEqual(rb.body.items.map((i) => i.ct), ['all', 'forB']);
  assert.equal(rb.body.items[0].sender, a.id);
  assert.equal(rb.body.items[1].to, b.id);
  assert.equal(typeof rb.body.now, 'number');
  const rc = await pull(g, c);
  assert.deepEqual(rc.body.items.map((i) => i.ct), ['all']);
  const ra = await pull(g, a);
  assert.deepEqual(ra.body.items.map((i) => i.ct), [], 'own items never come back');
});

test('revoke: device gets 410 everywhere, new writes impossible, seq returned', async () => {
  const { g, a } = await group();
  const m = await joinAndApprove(g, a);
  const p = await push(g, m, [{ iv: 'a', ct: 'legit', epoch: 1 }]);
  const r = await call('POST', `/v2/groups/${g}/devices/${m.id}/revoke`, a, {});
  assert.equal(r.status, 200);
  assert.ok(r.body.seq >= p.body.seqs[0]);
  assert.equal((await push(g, m, [{ iv: 'a', ct: 'evil', epoch: 1 }])).status, 410);
  assert.equal((await pull(g, m)).status, 410);
  // Re-join later with a fresh invite works (new token).
  const secret = await invite(g, a);
  const again = { ...m, token: rid() + rid() };
  const j = await call('POST', `/v2/groups/${g}/join`, again, { secret, device: m.id, x_pub: m.x, iv: 'a', ct: 'b' });
  assert.equal(j.status, 200);
  assert.ok([401, 410].includes((await pull(g, m)).status), 'old token stays dead');
  assert.equal((await pull(g, again)).body.status, 'pending', 'new token waits for approval');
});

test('the last admin can not be demoted, removed or leave members behind', async () => {
  const { g, a } = await group();
  const m = await joinAndApprove(g, a);
  assert.equal((await call('POST', `/v2/groups/${g}/devices/${a.id}/role`, a, { role: 'member' })).status, 409);
  assert.equal((await call('POST', `/v2/groups/${g}/devices/${a.id}/revoke`, a, {})).status, 409);
  assert.equal((await call('POST', `/v2/groups/${g}/leave`, a, {})).status, 409);
  // Promote a second admin: now either may step down.
  assert.equal((await call('POST', `/v2/groups/${g}/devices/${m.id}/role`, a, { role: 'admin' })).status, 200);
  assert.equal((await call('GET', `/v2/groups/${g}/joins`, m)).status, 200, 'promoted device is admin');
  assert.equal((await call('POST', `/v2/groups/${g}/devices/${a.id}/role`, m, { role: 'member' })).status, 200);
  assert.equal((await call('GET', `/v2/groups/${g}/joins`, a)).status, 403, 'demoted');
  assert.equal((await call('POST', `/v2/groups/${g}/leave`, a, {})).status, 200, 'members may leave');
  assert.equal((await pull(g, a)).status, 410);
});

test('purge: rows read by every active device are deleted; old unread rows flag a gap', async () => {
  const { g, a } = await group();
  const b = await joinAndApprove(g, a);
  const c = await joinAndApprove(g, a);
  const s = (await push(g, a, [{ iv: 'a', ct: 'one', epoch: 1 }, { iv: 'a', ct: 'two', epoch: 1 }])).body.seqs;
  // b read everything, c has not.
  await pull(g, b, s[1]);
  await fetch(`${BASE}/__scheduled?cron=17+3+*+*+*`);
  assert.equal((await pull(g, c, 0)).body.items.length, 2, 'unread by c → kept');
  await pull(g, c, s[1]);
  await pull(g, a, s[1]);
  await fetch(`${BASE}/__scheduled?cron=17+3+*+*+*`);
  // Make a row look 61 days old and unread by a new device d.
  const d = await joinAndApprove(g, a);
  const s2 = (await push(g, a, [{ iv: 'a', ct: 'old', epoch: 1 }])).body.seqs[0];
  execFileSync(process.env.WRANGLER || 'npx', [...(process.env.WRANGLER ? [] : ['wrangler']), 'd1', 'execute', 'inventory-sync', '--local',
    '--persist-to', process.env.PERSIST || '/tmp/wr-test', '--command',
    `UPDATE group_changes SET created_at = ${Date.now() - 61 * 24 * 3600 * 1000} WHERE seq = ${s2}`], { stdio: 'ignore' });
  await fetch(`${BASE}/__scheduled?cron=17+3+*+*+*`);
  const rd = await pull(g, d, 0);
  assert.equal(rd.body.items.length, 0);
  assert.equal(rd.body.gap, true, 'd missed a purged row → must resync');
  const rb = await pull(g, b, s2);
  assert.equal(rb.body.gap, false, 'b is past it');
});

test('v1 pair API still works (old app versions)', async () => {
  const pair = rid(); const tok = rid() + rid();
  const h = { authorization: `Bearer ${tok}`, 'content-type': 'application/json' };
  let r = await fetch(`${BASE}/v1/pairs/${pair}/changes`, { method: 'POST', headers: h, body: JSON.stringify({ sender: rid(), items: [{ iv: 'a', ct: 'b' }] }) });
  assert.equal(r.status, 200);
  r = await fetch(`${BASE}/v1/pairs/${pair}/changes?device=${rid()}&after=0`, { headers: h });
  assert.equal((await r.json()).items.length, 1);
});
