import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/sync/sync_crypto.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';

import 'sync_test_harness.dart';

/// The relay as deployed today: old pair mailboxes only, every /v2 route
/// answers 404 `not_found` (until the group update is deployed).
class _V1OnlyRelay extends FakeRelay implements GroupTransport {
  Never _missing() => throw const SyncServerException(404, 'not_found');
  @override
  Future<void> createGroup(GroupAuth auth, {required String publicKey}) async =>
      _missing();
  @override
  Future<void> addInvite(GroupAuth auth,
          {required String secretHash, required int expiresAt}) async =>
      _missing();
  @override
  Future<void> join(GroupAuth auth,
          {required String secret,
          required String publicKey,
          required SealedBlob request}) async =>
      _missing();
  @override
  Future<List<GroupJoinRequest>> joinRequests(GroupAuth auth) async => _missing();
  @override
  Future<int> approve(GroupAuth auth, String deviceId, {required String role}) async =>
      _missing();
  @override
  Future<void> reject(GroupAuth auth, String deviceId) async => _missing();
  @override
  Future<int> revoke(GroupAuth auth, String deviceId) async => _missing();
  @override
  Future<void> setRole(GroupAuth auth, String deviceId, String role) async =>
      _missing();
  @override
  Future<void> leave(GroupAuth auth) async => _missing();
  @override
  Future<List<int>> pushGroup(GroupAuth auth, List<GroupItem> items) async =>
      _missing();
  @override
  Future<GroupPullPage> pullGroup(GroupAuth auth, {required int after}) async =>
      _missing();
}

/// Nov 13 phone test: no QR ever showed because starting a group failed on
/// the not-yet-updated server with a generic "sync problem".
void main() {
  late _V1OnlyRelay relay;
  late TestDevice a, b;
  final now = DateTime(2026, 11, 13, 18);
  DateTime clock() => now;

  setUp(() async {
    relay = _V1OnlyRelay();
    a = await TestDevice.create(relay, clock: clock);
    b = await TestDevice.create(relay, clock: clock);
  });

  test('start group on the old server: clear error, nothing half-created',
      () async {
    await expectLater(
      a.engine.createGroup(),
      throwsA(isA<GroupError>().having((e) => e.code, 'code', 'server_update')),
    );
    expect((await a.engine.groupInfo()).state, GroupState.none);
    // The user can try again later without "already in a group".
    await expectLater(
      a.engine.createGroup(),
      throwsA(isA<GroupError>().having((e) => e.code, 'code', 'server_update')),
    );
  });

  test('joining on the old server says so instead of "code expired"',
      () async {
    final inv = GroupInvitePayload(
      groupId: 'g' * 24,
      adminId: (await a.engine.identity()).deviceId,
      adminKey: (await a.engine.identity()).publicKey,
      adminSignKey: (await a.engine.signer()).publicKey,
      secret: 'secret',
    );
    await expectLater(
      b.engine.joinGroup(inv),
      throwsA(isA<GroupError>().having((e) => e.code, 'code', 'server_update')),
    );
    expect((await b.engine.groupInfo()).state, GroupState.none);
  });

  test('direct two-way pairing still works on the old server', () async {
    await a.addItem('i1', 'Bread', at: now);
    await pairDevices(a, b);
    await settle(a, b);
    expect([for (final p in await a.engine.peers()) p.status], ['active']);
    expect([for (final p in await b.engine.peers()) p.status], ['active']);
    expect(await b.item('i1'), isNotNull);
  });
}
