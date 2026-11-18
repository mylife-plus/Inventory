import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/media/local_image_store.dart';
import 'package:inventory_app/core/sync/sync_config.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:inventory_app/data/repositories/repositories.dart';

enum SyncStatus { idle, syncing, ok, offline, error }

class SyncState {
  const SyncState({
    this.available = true,
    this.peers = const [],
    this.status = SyncStatus.idle,
    this.lastOkAt,
    this.group = const GroupInfo(),
  });

  /// False on web (no device sync there).
  final bool available;
  final List<SyncPeer> peers;
  final SyncStatus status;
  final DateTime? lastOkAt;

  /// v2 admin-managed group (none until this device starts or joins one).
  final GroupInfo group;

  /// Anything to sync at all: old-style pairs or a group.
  bool get hasSync =>
      peers.isNotEmpty ||
      group.state == GroupState.active ||
      group.state == GroupState.joining;

  /// Other devices this one syncs with (group members, else old pairs).
  int get activeCount => group.state == GroupState.active
      ? group.activeMembers.length - 1
      : peers.where((p) => p.isActive).length;

  SyncState copyWith({
    List<SyncPeer>? peers,
    SyncStatus? status,
    DateTime? lastOkAt,
    GroupInfo? group,
  }) =>
      SyncState(
        available: available,
        peers: peers ?? this.peers,
        status: status ?? this.status,
        lastOkAt: lastOkAt ?? this.lastOkAt,
        group: group ?? this.group,
      );
}

SyncEngine _buildEngine(AppDatabase db) => SyncEngine(
      database: () => db.database,
      transport: HttpSyncTransport(kSyncServerUrl),
      photoDir: () async =>
          kIsWeb ? null : (await LocalImageStore.ensureDir()).path,
    );

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => _buildEngine(ref.watch(databaseProvider)),
);

/// Erase Data: tell the relay to drop every pair (≤ 4 s, best effort) and
/// forget this device's identity, pairing keys and paired devices.
Future<void> forgetSyncForErase() async {
  if (kIsWeb) return;
  try {
    await _buildEngine(AppDatabase.instance)
        .forgetEverything()
        .timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('Sync forget: $e');
  }
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Runs sync while the app is open: polls every few seconds, scans right
/// after local writes (via the data providers), once on resume. Does
/// nothing — no network at all — until a device is paired.
class SyncController extends Notifier<SyncState> {
  Timer? _poll;
  Timer? _scanTimer;
  Timer? _debounce;
  AppLifecycleListener? _life;
  bool _running = false;
  bool _again = false;
  bool _full = false;
  bool _resumed = true;

  SyncEngine get _engine => ref.read(syncEngineProvider);

  @override
  SyncState build() {
    if (kIsWeb) return const SyncState(available: false);
    void onData(Object? _, Object? _) => _schedule();
    ref.listen(inventoryItemsProvider, onData);
    ref.listen(categoriesProvider, onData);
    ref.listen(customersProvider, onData);
    ref.listen(salesProvider, onData);
    ref.listen(shopSettingsProvider, onData);
    _life = AppLifecycleListener(
      onResume: () {
        _resumed = true;
        _schedule(immediate: true);
      },
      onPause: () => _resumed = false,
    );
    // Frequent poll = pull/push only (no full scan unless the DB changed);
    // the slower scan timer, resume and local edits run a full pass.
    _poll = Timer.periodic(kSyncPollInterval, (_) => _tick(full: false));
    _scanTimer = Timer.periodic(kSyncScanInterval, (_) => _tick());
    ref.onDispose(() {
      _poll?.cancel();
      _scanTimer?.cancel();
      _debounce?.cancel();
      _life?.dispose();
    });
    Future.microtask(() async {
      await reloadPeers();
      _schedule(immediate: true);
    });
    return const SyncState();
  }

  Future<void> reloadPeers() async {
    try {
      final peers = await _engine.peers();
      final group = await _engine.groupInfo();
      state = state.copyWith(peers: peers, group: group);
    } catch (e) {
      debugPrint('Sync peers: $e');
    }
  }

  void _schedule({bool immediate = false}) {
    if (!state.hasSync) return;
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 800),
      _tick,
    );
  }

  Future<void> _tick({bool full = true}) async {
    if (!_resumed || !state.hasSync) return;
    if (full) _full = true;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final f = _full;
        _full = false;
        await _runOnce(full: f);
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _runOnce({required bool full}) async {
    final quiet = state.status == SyncStatus.ok;
    if (!quiet) state = state.copyWith(status: SyncStatus.syncing);
    SyncRunResult r;
    try {
      r = await _engine.syncOnce(skipUnchangedScan: !full);
    } catch (e) {
      debugPrint('Sync failed: $e');
      r = SyncRunResult(error: e);
    }
    if (r.applied > 0) await _refreshData();
    final peers = await _engine.peers();
    final group = await _engine.groupInfo();
    if (await _engine.takeJoinDeclined()) _declined = true;
    state = state.copyWith(
      peers: peers,
      group: group,
      status: r.ok
          ? SyncStatus.ok
          : (r.offline ? SyncStatus.offline : SyncStatus.error),
      lastOkAt: r.ok ? DateTime.now() : null,
    );
  }

  /// Remote changes landed in SQLite: reload what the screens show.
  Future<void> _refreshData() async {
    await Future.wait([
      ref.read(shopSettingsProvider.notifier).refresh(),
      ref.read(categoriesProvider.notifier).refresh(),
      ref.read(inventoryItemsProvider.notifier).refresh(),
      ref.read(customersProvider.notifier).refresh(),
      ref.read(salesProvider.notifier).refresh(),
    ]);
  }

  Future<String> pairingCode() => _engine.pairingCode();

  Future<String> myDeviceId() async => (await _engine.identity()).deviceId;

  Future<void> confirmPeer(PairingPayload scanned, String name) async {
    await _engine.confirmPeer(scanned, name);
    await reloadPeers();
    _schedule(immediate: true);
  }

  Future<void> removePeer(String peerId) async {
    await _engine.removePeer(peerId);
    await reloadPeers();
    if (!state.hasSync) state = state.copyWith(status: SyncStatus.idle);
  }

  bool _declined = false;

  /// One-shot: the admin declined this device's join request.
  bool takeDeclined() {
    final d = _declined;
    _declined = false;
    return d;
  }

  Future<void> _after() async {
    await reloadPeers();
    _schedule(immediate: true);
  }

  // ---------------------------------------------------------- v2 groups

  Future<void> createGroup() async {
    await _engine.createGroup();
    await _after();
  }

  Future<String> createInvite() => _engine.createInvite();

  Future<void> joinGroup(GroupInvitePayload invite) async {
    await _engine.joinGroup(invite);
    await _after();
  }

  Future<void> cancelJoin() async {
    await _engine.cancelJoin();
    await reloadPeers();
  }

  Future<void> approveJoin(String deviceId, String name) async {
    await _engine.approveJoin(deviceId, name);
    await _after();
  }

  Future<void> rejectJoin(String deviceId) async {
    await _engine.rejectJoin(deviceId);
    await reloadPeers();
  }

  Future<void> removeMember(String deviceId) async {
    await _engine.removeMember(deviceId);
    await _after();
  }

  Future<void> setMemberRole(String deviceId, {required bool admin}) async {
    await _engine.setMemberRole(deviceId, admin: admin);
    await _after();
  }

  Future<void> renameMember(String deviceId, String name) async {
    await _engine.renameMember(deviceId, name);
    await _after();
  }

  Future<void> leaveGroup() async {
    await _engine.leaveGroup();
    await reloadPeers();
    if (!state.hasSync) state = state.copyWith(status: SyncStatus.idle);
  }

  /// Admin: delete the group for every device (data stays on each).
  Future<void> dissolveGroup() async {
    await _engine.dissolveGroup();
    await reloadPeers();
    if (!state.hasSync) state = state.copyWith(status: SyncStatus.idle);
  }

  Future<List<SyncTrashEntry>> trash() => _engine.trash();

  Future<void> restoreTrash(List<int> ids) async {
    final n = await _engine.restoreTrash(ids);
    if (n > 0) await _refreshData();
    await _after();
  }

  Future<void> emptyTrash([List<int>? ids]) async {
    await _engine.emptyTrash(ids);
    await reloadPeers();
  }

  Future<void> syncNow() async {
    await reloadPeers();
    _schedule(immediate: true);
  }
}
