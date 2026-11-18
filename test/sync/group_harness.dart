import 'dart:convert';

import 'package:inventory_app/core/sync/sync_crypto.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';

import 'sync_test_harness.dart';

class RelayDevice {
  RelayDevice(this.token, this.xPub, {this.role = 'member', this.status = 'pending'});
  String token;
  String xPub;
  String role;
  String status;
  int start = 0;
  int cursor = 0;
  SealedBlob? join;
}

class RelayRow {
  RelayRow(this.seq, this.sender, this.to, this.epoch, this.blob, this.at);
  final int seq;
  final String sender;
  final String? to;
  final int epoch;
  final SealedBlob blob;
  final int at;
}

/// In-memory relay with the Worker's v1 AND v2 rules (sync-server/src).
class FakeGroupRelay extends FakeRelay implements GroupTransport {
  FakeGroupRelay({DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final DateTime Function() clock;

  final Map<String, Map<String, RelayDevice>> devs = {};
  final Map<String, ({String g, int exp, bool used})> invites = {};
  final Map<String, List<RelayRow>> rows = {};
  final Map<String, int> purged = {};
  final List<SealedBlob> everStoredGroup = [];
  int _gseq = 0;

  int get _ms => clock().millisecondsSinceEpoch;

  RelayDevice _caller(GroupAuth a) {
    if (offline) throw const SyncOfflineException();
    final d = devs[a.groupId]?[a.deviceId];
    if (d == null || d.token != a.token) {
      throw const SyncServerException(401, 'unauthorized');
    }
    if (d.status == 'revoked') throw const SyncServerException(410, 'revoked');
    return d;
  }

  RelayDevice _admin(GroupAuth a) {
    final d = _caller(a);
    if (d.status != 'active' || d.role != 'admin') {
      throw const SyncServerException(403, 'not_admin');
    }
    return d;
  }

  int _maxSeq(String g) => (rows[g] ?? const []).fold(0, (m, r) => r.seq > m ? r.seq : m);

  int _otherAdmins(String g, String d) => devs[g]!.entries
      .where((e) => e.key != d && e.value.status == 'active' && e.value.role == 'admin')
      .length;

  @override
  Future<void> createGroup(GroupAuth auth, {required String publicKey}) async {
    if (offline) throw const SyncOfflineException();
    if (devs.containsKey(auth.groupId)) throw const SyncServerException(409, 'exists');
    devs[auth.groupId] = {
      auth.deviceId: RelayDevice(auth.token, publicKey, role: 'admin', status: 'active'),
    };
  }

  @override
  Future<void> addInvite(GroupAuth auth, {required String secretHash, required int expiresAt}) async {
    _admin(auth);
    invites[secretHash] = (g: auth.groupId, exp: expiresAt, used: false);
  }

  @override
  Future<void> join(GroupAuth auth, {required String secret, required String publicKey, required SealedBlob request}) async {
    if (offline) throw const SyncOfflineException();
    final h = sha256Hex(utf8.encode(secret));
    final inv = invites[h];
    if (inv == null || inv.used || inv.g != auth.groupId || inv.exp < _ms) {
      throw const SyncServerException(403, 'invite_invalid');
    }
    invites[h] = (g: inv.g, exp: inv.exp, used: true);
    final g = devs[auth.groupId]!;
    if (g[auth.deviceId]?.status == 'active') {
      throw const SyncServerException(409, 'already_member');
    }
    g[auth.deviceId] = RelayDevice(auth.token, publicKey)..join = request;
  }

  @override
  Future<List<GroupJoinRequest>> joinRequests(GroupAuth auth) async {
    _admin(auth);
    return [
      for (final e in devs[auth.groupId]!.entries)
        if (e.value.status == 'pending')
          GroupJoinRequest(deviceId: e.key, publicKey: e.value.xPub, blob: e.value.join!),
    ];
  }

  @override
  Future<int> approve(GroupAuth auth, String deviceId, {required String role}) async {
    _admin(auth);
    final t = devs[auth.groupId]![deviceId];
    if (t == null || t.status != 'pending') throw const SyncServerException(409, 'not_pending');
    t
      ..status = 'active'
      ..role = role
      ..start = _maxSeq(auth.groupId)
      ..cursor = _maxSeq(auth.groupId)
      ..join = null;
    return t.start;
  }

  @override
  Future<void> reject(GroupAuth auth, String deviceId) async {
    _admin(auth);
    final g = devs[auth.groupId]!;
    if (g[deviceId]?.status == 'pending') g.remove(deviceId);
  }

  @override
  Future<int> revoke(GroupAuth auth, String deviceId) async {
    _admin(auth);
    final t = devs[auth.groupId]![deviceId];
    if (t == null || t.status == 'revoked') return _maxSeq(auth.groupId);
    if (t.status == 'active' && t.role == 'admin' && _otherAdmins(auth.groupId, deviceId) == 0) {
      throw const SyncServerException(409, 'last_admin');
    }
    t.status = 'revoked';
    return _maxSeq(auth.groupId);
  }

  @override
  Future<void> setRole(GroupAuth auth, String deviceId, String role) async {
    _admin(auth);
    final t = devs[auth.groupId]![deviceId];
    if (t == null || t.status != 'active') throw const SyncServerException(409, 'not_member');
    if (role == 'member' && t.role == 'admin' && _otherAdmins(auth.groupId, deviceId) == 0) {
      throw const SyncServerException(409, 'last_admin');
    }
    t.role = role;
  }

  @override
  Future<void> leave(GroupAuth auth) async {
    final me = _caller(auth);
    final g = devs[auth.groupId]!;
    if (me.status == 'active' && me.role == 'admin' && _otherAdmins(auth.groupId, auth.deviceId) == 0 &&
        g.entries.any((e) => e.key != auth.deviceId && e.value.status == 'active')) {
      throw const SyncServerException(409, 'last_admin');
    }
    me.status = 'revoked';
  }

  @override
  Future<List<int>> pushGroup(GroupAuth auth, List<GroupItem> items) async {
    final me = _caller(auth);
    if (me.status != 'active') throw const SyncServerException(403, 'not_active');
    final out = <int>[];
    for (final it in items) {
      (rows[auth.groupId] ??= []).add(RelayRow(++_gseq, auth.deviceId, it.to, it.epoch, it.blob, _ms));
      everStoredGroup.add(it.blob);
      out.add(_gseq);
    }
    return out;
  }

  @override
  Future<GroupPullPage> pullGroup(GroupAuth auth, {required int after}) async {
    final me = _caller(auth);
    if (me.status != 'active') {
      return GroupPullPage(items: const [], status: me.status, role: me.role, serverNow: _ms);
    }
    final from = after > me.start ? after : me.start;
    if (from > me.cursor) me.cursor = from;
    final gap = (purged[auth.groupId] ?? 0) > from;
    final list = [
      for (final r in rows[auth.groupId] ?? const <RelayRow>[])
        if (r.seq > from && r.sender != auth.deviceId && (r.to == null || r.to == auth.deviceId))
          GroupItem(seq: r.seq, sender: r.sender, to: r.to, epoch: r.epoch, blob: r.blob),
    ];
    return GroupPullPage(
      items: list.take(200).toList(),
      more: list.length > 200,
      status: 'active',
      role: me.role,
      serverNow: _ms,
      gap: gap,
    );
  }

  /// The daily cron: read-by-all rows, and rows older than [olderThanMs].
  void purge({int? olderThanMs}) {
    for (final g in rows.keys) {
      final act = devs[g]!.values.where((d) => d.status == 'active');
      final minCursor = act.isEmpty ? 0 : act.map((d) => d.cursor).reduce((a, b) => a < b ? a : b);
      final cutoff = olderThanMs == null ? null : _ms - olderThanMs;
      for (final r in rows[g]!) {
        if (cutoff != null && r.at <= cutoff && r.seq > (purged[g] ?? 0)) purged[g] = r.seq;
      }
      rows[g]!.removeWhere((r) => r.seq <= minCursor || (cutoff != null && r.at <= cutoff));
    }
  }
}

/// Admin invites, newcomer scans + requests, admin approves under [name].
Future<void> joinViaAdmin(
  TestDevice admin,
  TestDevice newcomer, {
  String name = 'Phone',
  bool asAdmin = false,
}) async {
  final code = await admin.engine.createInvite();
  await newcomer.engine.joinGroup(GroupInvitePayload.tryParse(code)!);
  await admin.engine.syncOnce();
  final info = await admin.engine.groupInfo();
  final me = (await newcomer.engine.identity()).deviceId;
  final req = info.joins.firstWhere((j) => j.deviceId == me);
  await admin.engine.approveJoin(req.deviceId, name, asAdmin: asAdmin);
}

/// Sync rounds over every device until nothing moves.
Future<void> settleAll(List<TestDevice> devices) async {
  for (var i = 0; i < 8; i++) {
    var moved = 0;
    for (final d in devices) {
      final r = await d.engine.syncOnce();
      moved += r.applied + r.pushed;
    }
    if (i > 1 && moved == 0) return;
  }
}

Future<GroupState> stateOf(TestDevice d) async => (await d.engine.groupInfo()).state;
