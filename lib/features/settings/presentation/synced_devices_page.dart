import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/sync/sync_controller.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/sync/sync_transport.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/scroll_chrome.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Settings → Synced Devices: the shop's device group. Admins add devices
/// (invite QR → Approve), promote/demote, rename and remove them, and see
/// the trash; other devices see the list. Devices still on the old
/// pairing are listed until they move into the group.
class SyncedDevicesPage extends ConsumerStatefulWidget {
  const SyncedDevicesPage({super.key});

  @override
  ConsumerState<SyncedDevicesPage> createState() => _SyncedDevicesPageState();
}

class _SyncedDevicesPageState extends ConsumerState<SyncedDevicesPage> {
  String? _deviceId;
  bool _busy = false;

  /// The relay does not have the admin-group update yet (until it is
  /// deployed): offer the direct two-way pairing instead.
  bool _serverOld = false;

  /// This device's direct-pairing QR (old two-way pairing).
  String? _pairCode;

  SyncController get _c => ref.read(syncControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!ref.read(syncControllerProvider).available) return;
    final id = await _c.myDeviceId();
    if (!mounted) return;
    setState(() => _deviceId = id);
    unawaited(_c.syncNow());
    if (ref.read(syncControllerProvider).peers.any((p) => !p.isActive && !p.isRemoved)) {
      unawaited(_loadPairCode());
    }
  }

  /// Rebuilt whenever the paired list changes: removing a device rotates
  /// the nonce, and a stale QR left both sides waiting forever.
  Future<void> _loadPairCode() async {
    if (!ref.read(syncControllerProvider).available) return;
    final code = await _c.pairingCode();
    if (mounted) setState(() => _pairCode = code);
  }

  void _onServerOld() {
    if (!_serverOld) setState(() => _serverOld = true);
    unawaited(_loadPairCode());
  }

  String _shortId(String id) =>
      (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();

  String _errorText(S t, Object e) {
    if (e is GroupError) {
      return switch (e.code) {
        'invite_invalid' => t('sync_err_invite'),
        'last_admin' => t('sync_err_last_admin'),
        'in_other_group' || 'already_member' => t('sync_err_other_group'),
        'own_code' => t('sync_own_code'),
        'server_update' => t('sync_err_server'),
        _ => t('sync_status_error'),
      };
    }
    if (e is SyncOfflineException) return t('sync_status_offline');
    return t('sync_status_error');
  }

  /// Runs a group action with one error notice for every failure.
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    final t = ref.read(tProvider);
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (e) {
      final old = e is GroupError && e.code == 'server_update';
      if (old && mounted) _onServerOld();
      if (mounted) {
        showTopNotice(
          context,
          _errorText(t, e),
          duration: Duration(milliseconds: old ? 6000 : 2800),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanInvite() async {
    final t = ref.read(tProvider);
    final raw = await context.push<String>('/settings/sync/scan');
    if (!mounted || raw == null) return;
    final invite = GroupInvitePayload.tryParse(raw);
    if (invite == null) {
      final direct = PairingPayload.tryParse(raw);
      final inGroup =
          ref.read(syncControllerProvider).group.state == GroupState.active;
      if (direct != null && !inGroup) {
        await _pairDirect(direct);
        return;
      }
      showTopNotice(
        context,
        direct != null ? t('sync_old_code') : t('sync_invalid_code'),
      );
      return;
    }
    if (invite.adminId == _deviceId) {
      showTopNotice(context, t('sync_own_code'));
      return;
    }
    final ok = await _run(() => _c.joinGroup(invite));
    if (!ok || !mounted) return;
    AppHaptics.medium();
    showTopNotice(context, t('sync_join_sent'), icon: Icons.check_circle_rounded);
  }

  /// Direct two-way pairing (works on the current relay): this side
  /// confirms the scanned phone, then that phone scans this one's code.
  Future<void> _pairDirect(PairingPayload payload) async {
    final t = ref.read(tProvider);
    if (payload.deviceId == _deviceId) {
      showTopNotice(context, t('sync_own_code'));
      return;
    }
    final name = await showSyncNameDialog(context, t);
    if (!mounted || name == null) return;
    final ok = await _run(() => _c.confirmPeer(payload, name));
    if (!ok || !mounted) return;
    _onServerOld(); // keep this phone's code on screen for the other side
    AppHaptics.medium();
    showTopNotice(
      context,
      t.tr('sync_paired_ok', {'name': name}),
      icon: Icons.check_circle_rounded,
    );
  }

  /// Makes this device the admin, then shows its join QR right away.
  Future<void> _startGroup(bool migrate) async {
    final t = ref.read(tProvider);
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('sync_start_title'),
      message: migrate ? t('sync_migrate_hint') : t('sync_start_q'),
      confirmLabel: t('sync_start_ok'),
    );
    if (!ok || !mounted) return;
    if (!await _run(_c.createGroup)) return;
    AppHaptics.medium();
    if (mounted) await _addDevice();
  }

  Future<void> _addDevice() async {
    final t = ref.read(tProvider);
    String? code;
    final ok = await _run(() async => code = await _c.createInvite());
    if (!ok || !mounted || code == null) return;
    await showDialog<void>(
      context: context,
      barrierColor: kAppScrim,
      builder: (_) => _InviteDialog(code: code!, t: t),
    );
  }

  Future<void> _approve(GroupJoinCandidate j) async {
    final t = ref.read(tProvider);
    final name = await showSyncNameDialog(context, t, initial: j.legacyName);
    if (!mounted || name == null) return;
    if (await _run(() => _c.approveJoin(j.deviceId, name))) {
      AppHaptics.medium();
      if (mounted) {
        showTopNotice(context, t.tr('sync_approved_ok', {'name': name}),
            icon: Icons.check_circle_rounded);
      }
    }
  }

  Future<void> _decline(GroupJoinCandidate j) async {
    final t = ref.read(tProvider);
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('sync_decline'),
      message: t.tr('sync_decline_q', {'id': _shortId(j.deviceId)}),
      confirmLabel: t('sync_decline'),
      destructive: true,
    );
    if (ok && mounted) await _run(() => _c.rejectJoin(j.deviceId));
  }

  Future<void> _memberAction(GroupMember m, _MemberAction a, String name) async {
    final t = ref.read(tProvider);
    switch (a) {
      case _MemberAction.rename:
        final v = await showSyncNameDialog(context, t, initial: m.name);
        if (v != null && mounted) await _run(() => _c.renameMember(m.deviceId, v));
      case _MemberAction.makeAdmin:
        await _run(() => _c.setMemberRole(m.deviceId, admin: true));
      case _MemberAction.removeAdmin:
        await _run(() => _c.setMemberRole(m.deviceId, admin: false));
      case _MemberAction.remove:
        final ok = await showAppConfirmDialog(
          context: context,
          title: t('sync_remove'),
          message: t.tr('sync_remove_device_q', {'name': name}),
          confirmLabel: t('sync_remove_btn'),
          destructive: true,
        );
        if (ok && mounted) await _run(() => _c.removeMember(m.deviceId));
    }
  }

  /// Leave group (client, Nov 14 + 16):
  /// * normal device: leaves (its data stays);
  /// * the only admin: always deletes the group for every device;
  /// * one of 2+ admins: chooses Leave (only this phone) or Delete group.
  Future<void> _leave() async {
    final t = ref.read(tProvider);
    final group = ref.read(syncControllerProvider).group;
    if (group.isAdmin && group.adminCount >= 2) {
      final choice = await showDialog<_LeaveChoice>(
        context: context,
        barrierColor: kAppScrim,
        builder: (_) => _LeaveChoiceDialog(t: t),
      );
      if (!mounted || choice == null) return;
      await _run(choice == _LeaveChoice.delete ? _c.dissolveGroup : _c.leaveGroup);
      return;
    }
    final admin = group.isAdmin;
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('sync_leave'),
      message: t(admin ? 'sync_dissolve_q' : 'sync_leave_q'),
      confirmLabel: t(admin ? 'sync_dissolve_ok' : 'sync_leave_ok'),
      destructive: true,
    );
    if (ok && mounted) await _run(admin ? _c.dissolveGroup : _c.leaveGroup);
  }

  Future<void> _removeLegacy(SyncPeer peer) async {
    final t = ref.read(tProvider);
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('sync_remove'),
      message: t.tr('sync_remove_q', {'name': peer.name}),
      confirmLabel: t('sync_remove_btn'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _c.removePeer(peer.peerId);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final sync = ref.watch(syncControllerProvider);
    final localeCode =
        ref.watch(appPrefsProvider).valueOrNull?.localeCode ?? 'en';
    final group = sync.group;
    ref.listen(syncControllerProvider.select((s) => s.group.state), (prev, next) {
      if (prev == GroupState.joining && next == GroupState.none &&
          _c.takeDeclined()) {
        showTopNotice(context, t('sync_join_declined'));
      }
      if (prev == GroupState.joining && next == GroupState.active) {
        AppHaptics.medium();
        showTopNotice(context, t('sync_join_approved'),
            icon: Icons.check_circle_rounded);
      }
    });
    ref.listen(syncControllerProvider.select((s) => s.peers.length), (_, _) {
      if (_pairCode != null) unawaited(_loadPairCode());
    });
    final fmt = DateFormat('d MMM, HH:mm', localeCode);
    final inGroup = group.state == GroupState.active;
    final legacy = sync.peers;
    final waiting = legacy.any((p) => !p.isActive && !p.isRemoved);

    String statusText() {
      switch (sync.status) {
        case SyncStatus.syncing:
          return t('sync_status_syncing');
        case SyncStatus.ok:
          return waiting && !inGroup
              ? t('sync_status_waiting')
              : t('sync_status_ok');
        case SyncStatus.offline:
          return t('sync_status_offline');
        case SyncStatus.error:
          return t('sync_status_error');
        case SyncStatus.idle:
          return '';
      }
    }

    final status = (inGroup || legacy.isNotEmpty) ? statusText() : '';
    final statusColor = switch (sync.status) {
      SyncStatus.ok when waiting && !inGroup => p.textSecondary,
      SyncStatus.ok => p.neon,
      SyncStatus.error => Colors.redAccent,
      _ => p.textSecondary,
    };

    String memberName(GroupMember m) {
      if (m.deviceId == _deviceId) return t('sync_this_device');
      return m.name.trim().isEmpty
          ? t.tr('sync_device_fallback', {'id': _shortId(m.deviceId)})
          : m.name;
    }

    String peerLine(SyncPeer peer) {
      if (peer.isRemoved) return t('sync_peer_removed');
      if (!peer.isActive) return t('sync_waiting');
      final at = peer.lastSyncAt;
      if (at == null) return t('sync_never');
      return t.tr('sync_last', {'time': fmt.format(at)});
    }

    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: p.textPrimary,
            ),
          ),
        );

    Widget hint(String text, {TextAlign align = TextAlign.center}) => Text(
          text,
          textAlign: align,
          style: TextStyle(
            color: p.textPrimary.withValues(alpha: 0.85),
            fontSize: 14,
            height: 1.35,
          ),
        );

    Widget cardTitle(String text) => Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: p.textPrimary,
          ),
        );

    ButtonStyle outlined() => OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.stroke),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        );

    Widget divided(List<Widget> rows) => Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 0.7,
                  indent: 16,
                  endIndent: 16,
                  color: p.stroke.withValues(alpha: 0.85),
                ),
              rows[i],
            ],
          ],
        );

    Widget legacySection() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            sectionTitle(inGroup ? t('sync_legacy_title') : t('sync_paired')),
            AppCard(
              key: const ValueKey('sync_legacy_list'),
              padding: EdgeInsets.zero,
              child: divided([
                for (final peer in legacy)
                  _PeerRow(
                    name: peer.name,
                    subtitle: peerLine(peer),
                    active: peer.isActive,
                    removed: peer.isRemoved,
                    onRemove: () => _removeLegacy(peer),
                  ),
              ]),
            ),
            if (inGroup) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  t('sync_legacy_hint'),
                  style: TextStyle(color: p.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ],
        );

    Widget directCard() => AppCard(
          key: const ValueKey('sync_direct_card'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
              cardTitle(t('sync_direct_title')),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  width: 196,
                  height: 196,
                  child: _pairCode == null
                      ? const Center(child: CircularProgressIndicator())
                      : QrImageView(
                          key: const ValueKey('sync_my_qr'),
                          data: _pairCode!,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                        ),
                ),
              ),
              if (_deviceId != null) ...[
                const SizedBox(height: 8),
                Text(
                  t.tr('sync_device_id', {'id': _shortId(_deviceId!)}),
                  style: TextStyle(color: p.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              hint(t('sync_my_device_hint')),
              const SizedBox(height: 14),
              AccentButton(
                key: const ValueKey('sync_direct_scan'),
                label: t('sync_scan'),
                icon: Icons.qr_code_scanner_rounded,
                onPressed: _busy ? null : _scanInvite,
              ),
            ],
          ),
        );

    List<Widget> notInGroup() => [
          if (group.state == GroupState.removed)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AppCard(
                key: const ValueKey('sync_removed_card'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  children: [
                    Icon(Icons.link_off_rounded, color: p.textSecondary, size: 26),
                    const SizedBox(width: 12),
                    Expanded(child: hint(t('sync_removed_body'), align: TextAlign.start)),
                  ],
                ),
              ),
            ),
          // Until the relay has the group update, direct pairing comes first.
          if (_serverOld || waiting) ...[
            directCard(),
            const SizedBox(height: 16),
          ],
          // The admin side: shows the join QR (after one confirm).
          AppCard(
            key: const ValueKey('sync_start_card'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                cardTitle(t('sync_start_title')),
                const SizedBox(height: 12),
                hint(legacy.isNotEmpty ? t('sync_migrate_hint') : t('sync_start_hint')),
                const SizedBox(height: 14),
                AccentButton(
                  key: const ValueKey('sync_start_button'),
                  label: t('sync_show_qr'),
                  icon: Icons.qr_code_2_rounded,
                  onPressed: _busy ? null : () => _startGroup(legacy.isNotEmpty),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // The new device: scans the admin's QR.
          AppCard(
            key: const ValueKey('sync_join_card'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                cardTitle(t('sync_join_title')),
                const SizedBox(height: 12),
                hint(t('sync_join_hint')),
                if (_deviceId != null && !(_serverOld || waiting)) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.tr('sync_device_id', {'id': _shortId(_deviceId!)}),
                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey('sync_scan_button'),
                  onPressed: _busy ? null : _scanInvite,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: _oneLine(t('sync_scan_admin')),
                  style: outlined(),
                ),
              ],
            ),
          ),
          if (legacy.isNotEmpty) legacySection(),
        ];

    List<Widget> joining() => [
          AppCard(
            key: const ValueKey('sync_join_waiting'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                Icon(Icons.hourglass_top_rounded, color: p.neon, size: 30),
                const SizedBox(height: 10),
                cardTitle(t('sync_join_waiting')),
                const SizedBox(height: 8),
                hint(t('sync_join_waiting_hint')),
                if (_deviceId != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    t.tr('sync_device_id', {'id': _shortId(_deviceId!)}),
                    key: const ValueKey('sync_join_code'),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton(
                  key: const ValueKey('sync_join_cancel'),
                  onPressed: _busy ? null : () => _run(_c.cancelJoin),
                  child: _oneLine(t('cancel')),
                ),
              ],
            ),
          ),
          if (legacy.isNotEmpty) legacySection(),
        ];

    List<Widget> active() {
      final doc = group.doc;
      final members = [...?doc?.active]..sort((a, b) {
          if (a.deviceId == _deviceId) return -1;
          if (b.deviceId == _deviceId) return 1;
          if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      final admin = group.isAdmin;
      return [
        if (admin)
          for (final j in group.joins)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                key: ValueKey('sync_join_request_${j.deviceId}'),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                borderColor: p.neon,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.phonelink_ring_rounded, color: p.neon, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                j.legacyName ?? t('sync_request_title'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.tr('sync_request_body', {'id': _shortId(j.deviceId)}),
                                style: TextStyle(color: p.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: const ValueKey('sync_decline_button'),
                          onPressed: _busy ? null : () => _decline(j),
                          style: TextButton.styleFrom(
                            foregroundColor: p.textSecondary,
                          ),
                          child: _oneLine(t('sync_decline'), weight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        // Same look as the app's confirm dialogs.
                        FilledButton(
                          key: const ValueKey('sync_approve_button'),
                          onPressed: _busy ? null : () => _approve(j),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.fab,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _oneLine(t('sync_approve'), weight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        if (admin) ...[
          OutlinedButton.icon(
            key: const ValueKey('sync_add_device'),
            onPressed: _busy ? null : _addDevice,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: _oneLine(t('sync_add_device')),
            style: outlined(),
          ),
          if (group.adminCount < 2 && members.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t('sync_two_admins_hint'),
                    key: const ValueKey('sync_two_admins_hint'),
                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
        ],
        sectionTitle(t('sync_devices_title')),
        AppCard(
          key: const ValueKey('sync_member_list'),
          padding: EdgeInsets.zero,
          child: divided([
            for (final m in members)
              _MemberRow(
                name: memberName(m),
                subtitle: m.deviceId == _deviceId
                    ? (group.lastSyncAt == null
                        ? t('sync_never')
                        : t.tr('sync_last', {'time': fmt.format(group.lastSyncAt!)}))
                    : t.tr('sync_device_id', {'id': _shortId(m.deviceId)}),
                isAdmin: m.isAdmin,
                adminLabel: t('sync_admin_badge'),
                isMe: m.deviceId == _deviceId,
                actions: !admin
                    ? const []
                    : [
                        if (m.deviceId != _deviceId) _MemberAction.rename,
                        if (!m.isAdmin) _MemberAction.makeAdmin,
                        if (m.isAdmin && group.adminCount > 1) _MemberAction.removeAdmin,
                        if (m.deviceId != _deviceId) _MemberAction.remove,
                      ],
                actionLabel: (a) => switch (a) {
                  _MemberAction.rename => t('sync_rename'),
                  _MemberAction.makeAdmin => t('sync_make_admin'),
                  _MemberAction.removeAdmin => t('sync_remove_admin'),
                  _MemberAction.remove => t('sync_remove'),
                },
                onAction: (a) => _memberAction(m, a, memberName(m)),
              ),
          ]),
        ),
        if (admin) ...[
          const SizedBox(height: 16),
          AppCard(
            key: const ValueKey('sync_trash_row'),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            onTap: () => context.push('/settings/sync/trash'),
            child: Row(
              children: [
                Icon(Icons.restore_from_trash_rounded, color: p.textPrimary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('sync_trash'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('sync_trash_hint'),
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${group.trashCount}',
                  style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w700),
                ),
                Icon(Icons.chevron_right_rounded, color: p.textSecondary),
              ],
            ),
          ),
        ],
        if (legacy.isNotEmpty) legacySection(),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            key: const ValueKey('sync_leave_button'),
            onPressed: _busy ? null : _leave,
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: _oneLine(t('sync_leave')),
          ),
        ),
      ];
    }

    return ScrollChromeHost(
      scrollTopHeroTag: 'scroll_top_synced_devices',
      builder: (context, chrome) {
        return CustomScrollView(
          controller: chrome.scrollController,
          physics: kScrollChromePhysics,
          slivers: [
            ...ScrollChrome.headerSlivers(
              context: context,
              chrome: chrome,
              header: (_) => ScrollChromeAppBar(
                chrome: chrome,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🔄', style: TextStyle(fontSize: 20, height: 1)),
                    const SizedBox(width: 8),
                    Text(
                      t('synced_devices'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (!sync.available)
                    EmptyState(
                      icon: Icons.devices_other_rounded,
                      title: t('sync_web'),
                    )
                  else ...[
                    if (status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              switch (sync.status) {
                                SyncStatus.ok when waiting && !inGroup =>
                                  Icons.hourglass_top_rounded,
                                SyncStatus.ok => Icons.check_circle_rounded,
                                SyncStatus.offline => Icons.cloud_off_rounded,
                                SyncStatus.error => Icons.error_outline_rounded,
                                _ => Icons.sync_rounded,
                              },
                              size: 16,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status,
                              key: const ValueKey('sync_status'),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...switch (group.state) {
                      GroupState.active => active(),
                      GroupState.joining => joining(),
                      _ => notInGroup(),
                    },
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: p.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            t('sync_encrypted_note'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _MemberAction { rename, makeAdmin, removeAdmin, remove }

enum _LeaveChoice { leave, delete }

/// One of several admins taps Leave: only this phone leaves, or the whole
/// group is deleted. Stacked full-width buttons keep every label one line.
class _LeaveChoiceDialog extends StatelessWidget {
  const _LeaveChoiceDialog({required this.t});

  final S t;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Dialog(
      key: const ValueKey('sync_leave_choice'),
      backgroundColor: p.cardElevated,
      elevation: 10,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('sync_leave'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t('sync_leave_choice_q'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, height: 1.35, fontSize: 14),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('sync_choice_leave'),
              onPressed: () => Navigator.pop(context, _LeaveChoice.leave),
              style: FilledButton.styleFrom(
                backgroundColor: p.fab,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: shape,
              ),
              child: _oneLine(t('sync_leave_ok'), weight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('sync_choice_delete'),
              onPressed: () => Navigator.pop(context, _LeaveChoice.delete),
              style: FilledButton.styleFrom(
                backgroundColor: p.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: shape,
              ),
              child: _oneLine(t('sync_delete_group'), weight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                t('cancel'),
                maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w700, color: p.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Button label that always stays on one line: long translations shrink a
/// little instead of wrapping (client, Nov 13).
Widget _oneLine(String text, {FontWeight? weight}) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: weight == null ? null : TextStyle(fontWeight: weight),
      ),
    );

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.subtitle,
    required this.isAdmin,
    required this.adminLabel,
    required this.isMe,
    required this.actions,
    required this.actionLabel,
    required this.onAction,
  });

  final String name;
  final String subtitle;
  final bool isAdmin;
  final String adminLabel;
  final bool isMe;
  final List<_MemberAction> actions;
  final String Function(_MemberAction) actionLabel;
  final void Function(_MemberAction) onAction;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Row(
        children: [
          Icon(Icons.phone_android_rounded, color: p.neon, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.neon.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: p.neon.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          adminLabel,
                          style: TextStyle(
                            color: p.neon,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (actions.isEmpty)
            const SizedBox(width: 48, height: 48)
          else
            PopupMenuButton<_MemberAction>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: p.textPrimary.withValues(alpha: 0.7),
              ),
              color: p.cardElevated,
              onSelected: onAction,
              itemBuilder: (_) => [
                for (final a in actions)
                  PopupMenuItem(
                    value: a,
                    child: Text(
                      actionLabel(a),
                      style: TextStyle(
                        color: a == _MemberAction.remove
                            ? Colors.redAccent
                            : p.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Admin's one-time invite QR. Closes by itself once a device has scanned
/// it and its request is waiting for Approve.
class _InviteDialog extends ConsumerWidget {
  const _InviteDialog({required this.code, required this.t});

  final String code;
  final S t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    ref.listen(syncControllerProvider.select((s) => s.group.joins.length),
        (prev, next) {
      if (next > (prev ?? 0) && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return Dialog(
      backgroundColor: p.cardElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('sync_invite_title'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox(
                width: 196,
                height: 196,
                child: QrImageView(
                  key: const ValueKey('sync_invite_qr'),
                  data: code,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t('sync_invite_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textPrimary.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('sync_invite_expiry'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, fontSize: 12),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('sync_invite_close'),
                onPressed: () => Navigator.pop(context),
                child: _oneLine(t('done')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name for a scanned device: starts empty, Confirm only works once a
/// name is typed (client, Nov 11).
/// [initial]: prefilled name (rename, or the name an old pairing used).
Future<String?> showSyncNameDialog(
  BuildContext context,
  S t, {
  String? initial,
}) =>
    showDialog<String>(
      context: context,
      barrierColor: kAppScrim,
      builder: (_) => _SyncNameDialog(t: t, initial: initial),
    );

/// Owns its controller so it lives through the dialog's close animation
/// (disposing it right after `showDialog` returned crashed in debug).
class _SyncNameDialog extends StatefulWidget {
  const _SyncNameDialog({required this.t, this.initial});

  final S t;
  final String? initial;

  @override
  State<_SyncNameDialog> createState() => _SyncNameDialogState();
}

class _SyncNameDialogState extends State<_SyncNameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = widget.t;
    return Dialog(
      backgroundColor: p.cardElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('sync_name_title'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('sync_name_body'),
              style: TextStyle(color: p.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('sync_name_field'),
              controller: _ctrl,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: t('sync_name_hint')),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: _oneLine(t('cancel')),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (_, v, _) => FilledButton(
                    key: const ValueKey('sync_name_confirm'),
                    onPressed: v.text.trim().isEmpty ? null : _submit,
                    child: _oneLine(t('sync_confirm')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.name,
    required this.subtitle,
    required this.active,
    required this.onRemove,
    this.removed = false,
  });

  final String name;
  final String subtitle;
  final bool active;
  final bool removed;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Row(
        children: [
          Icon(
            active
                ? Icons.phone_android_rounded
                : (removed
                      ? Icons.link_off_rounded
                      : Icons.hourglass_top_rounded),
            color: active ? p.neon : p.textSecondary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: p.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera page that returns the first device-sync code it sees.
class SyncScanPage extends ConsumerStatefulWidget {
  const SyncScanPage({super.key});

  @override
  ConsumerState<SyncScanPage> createState() => _SyncScanPageState();
}

class _SyncScanPageState extends ConsumerState<SyncScanPage> {
  late final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    final s = _scanner;
    unawaited(() async {
      try {
        await s.stop();
      } catch (_) {}
      try {
        await s.dispose();
      } catch (_) {}
    }());
    super.dispose();
  }

  void _onDetect(String raw) {
    if (_done) return;
    // Admin invite (or an old-style code, to explain it is outdated).
    if (GroupInvitePayload.tryParse(raw) == null &&
        PairingPayload.tryParse(raw) == null) {
      return; // keep looking
    }
    _done = true;
    AppHaptics.medium();
    context.pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(t('sync_scan')),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      MobileScanner(
                        controller: _scanner,
                        fit: BoxFit.cover,
                        onDetect: (capture) {
                          for (final b in capture.barcodes) {
                            final v = b.rawValue;
                            if (v != null && v.isNotEmpty) _onDetect(v);
                          }
                        },
                        errorBuilder: (context, error) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              t.tr('camera_error', {
                                'code': '${error.errorCode}',
                              }),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 230,
                            height: 230,
                            decoration: BoxDecoration(
                              border: Border.all(color: p.neon, width: 2.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                t('sync_scan_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin: records deleted by non-admin devices (kept 30 days).
class SyncTrashPage extends ConsumerStatefulWidget {
  const SyncTrashPage({super.key});

  @override
  ConsumerState<SyncTrashPage> createState() => _SyncTrashPageState();
}

class _SyncTrashPageState extends ConsumerState<SyncTrashPage> {
  List<SyncTrashEntry>? _items;

  SyncController get _c => ref.read(syncControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final items = await _c.trash();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _restore(List<int> ids) async {
    final t = ref.read(tProvider);
    await _c.restoreTrash(ids);
    await _load();
    if (!mounted) return;
    AppHaptics.medium();
    showTopNotice(context, t('sync_restored'), icon: Icons.check_circle_rounded);
  }

  Future<void> _empty() async {
    final t = ref.read(tProvider);
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('sync_empty_trash'),
      message: t('sync_empty_trash_q'),
      confirmLabel: t('sync_empty_ok'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _c.emptyTrash();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final localeCode =
        ref.watch(appPrefsProvider).valueOrNull?.localeCode ?? 'en';
    final fmt = DateFormat('d MMM, HH:mm', localeCode);
    final doc = ref.watch(syncControllerProvider.select((s) => s.group.doc));
    final items = _items;

    String who(String id) {
      final m = doc?.member(id);
      if (m != null && m.name.trim().isNotEmpty) return m.name;
      final short = (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();
      return t.tr('sync_device_fallback', {'id': short});
    }

    IconData icon(String kind) => switch (kind) {
          'item' => Icons.inventory_2_rounded,
          'sale' => Icons.receipt_long_rounded,
          'cust' => Icons.person_rounded,
          _ => Icons.label_rounded,
        };

    String kindLabel(String kind) => switch (kind) {
          'item' => t('sync_kind_item'),
          'sale' => t('sync_kind_sale'),
          'cust' => t('sync_kind_cust'),
          _ => t('sync_kind_cat'),
        };

    return ScrollChromeHost(
      scrollTopHeroTag: 'scroll_top_sync_trash',
      builder: (context, chrome) {
        return CustomScrollView(
          controller: chrome.scrollController,
          physics: kScrollChromePhysics,
          slivers: [
            ...ScrollChrome.headerSlivers(
              context: context,
              chrome: chrome,
              header: (_) => ScrollChromeAppBar(
                chrome: chrome,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🗑️', style: TextStyle(fontSize: 20, height: 1)),
                    const SizedBox(width: 8),
                    Text(
                      t('sync_trash'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (items == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (items.isEmpty)
                    EmptyState(
                      icon: Icons.delete_outline_rounded,
                      title: t('sync_trash_empty'),
                      subtitle: t('sync_trash_hint'),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        t('sync_trash_hint'),
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                    ),
                    AppCard(
                      key: const ValueKey('sync_trash_list'),
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 0.7,
                                indent: 16,
                                endIndent: 16,
                                color: p.stroke.withValues(alpha: 0.85),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                              child: Row(
                                children: [
                                  Icon(icon(items[i].kind),
                                      color: p.textSecondary, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          items[i].title.isEmpty
                                              ? kindLabel(items[i].kind)
                                              : '${kindLabel(items[i].kind)} · ${items[i].title}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: p.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          t.tr('sync_trash_by', {
                                            'name': who(items[i].byDevice),
                                            'time': fmt.format(items[i].deletedAt),
                                          }),
                                          style: TextStyle(
                                              color: p.textSecondary, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey('sync_restore_${items[i].id}'),
                                    tooltip: t('sync_restore'),
                                    onPressed: () => _restore([items[i].id]),
                                    icon: Icon(Icons.restore_rounded, color: p.neon),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AccentButton(
                      key: const ValueKey('sync_restore_all'),
                      label: t('sync_restore_all'),
                      icon: Icons.restore_rounded,
                      onPressed: () => _restore([for (final e in items) e.id]),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        key: const ValueKey('sync_empty_trash'),
                        onPressed: _empty,
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        child: _oneLine(t('sync_empty_trash')),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}
