import 'dart:convert';
import 'dart:typed_data';

import 'package:inventory_app/core/sync/sync_crypto.dart';
import 'package:inventory_app/core/sync/sync_merge.dart';

/// One device of the shop group, as listed in the admin-signed member list.
class GroupMember {
  const GroupMember({
    required this.deviceId,
    required this.name,
    required this.role,
    required this.status,
    required this.publicKey,
    required this.signKey,
    required this.addedAt,
    this.removedAt,
    this.removedSeq,
  });

  final String deviceId;
  final String name;

  /// `admin` or `member`.
  final String role;

  /// `active` or `removed`.
  final String status;
  final Uint8List publicKey; // X25519
  final Uint8List signKey; // Ed25519
  final int addedAt;

  /// When an admin removed it, and the mailbox position at that moment:
  /// everything it wrote after that is ignored, even if someone relays it.
  final int? removedAt;
  final int? removedSeq;

  bool get isAdmin => role == 'admin' && isActive;
  bool get isActive => status == 'active';

  GroupMember copyWith({
    String? name,
    String? role,
    String? status,
    int? removedAt,
    int? removedSeq,
    bool clearRemoval = false,
  }) =>
      GroupMember(
        deviceId: deviceId,
        name: name ?? this.name,
        role: role ?? this.role,
        status: status ?? this.status,
        publicKey: publicKey,
        signKey: signKey,
        addedAt: addedAt,
        removedAt: clearRemoval ? null : (removedAt ?? this.removedAt),
        removedSeq: clearRemoval ? null : (removedSeq ?? this.removedSeq),
      );

  Map<String, Object?> toJson() => {
        'd': deviceId,
        'n': name,
        'r': role,
        'st': status,
        'x': b64(publicKey),
        's': b64(signKey),
        'a': addedAt,
        if (removedAt != null) 'ra': removedAt,
        if (removedSeq != null) 'rq': removedSeq,
      };

  static GroupMember? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final role = j['r'], st = j['st'];
      if (role != 'admin' && role != 'member') return null;
      if (st != 'active' && st != 'removed') return null;
      final x = base64Decode(j['x'] as String);
      final s = base64Decode(j['s'] as String);
      if (x.length != 32 || s.length != 32) return null;
      return GroupMember(
        deviceId: j['d'] as String,
        name: '${j['n'] ?? ''}',
        role: role as String,
        status: st as String,
        publicKey: x,
        signKey: s,
        addedAt: (j['a'] as num).toInt(),
        removedAt: (j['ra'] as num?)?.toInt(),
        removedSeq: (j['rq'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Versioned member list, signed by an admin. Every device keeps the newest
/// one it could verify; only an admin of the previous list can issue the
/// next one.
class MemberDoc {
  const MemberDoc({
    required this.groupId,
    required this.version,
    required this.epoch,
    required this.issuedAt,
    required this.signer,
    required this.members,
    this.signature,
  });

  final String groupId;
  final int version;

  /// Group key generation in use from this version on.
  final int epoch;
  final int issuedAt;
  final String signer;
  final List<GroupMember> members;
  final Uint8List? signature;

  GroupMember? member(String deviceId) {
    for (final m in members) {
      if (m.deviceId == deviceId) return m;
    }
    return null;
  }

  List<GroupMember> get active => members.where((m) => m.isActive).toList();
  List<GroupMember> get admins => members.where((m) => m.isAdmin).toList();

  Map<String, Object?> _body() => {
        'g': groupId,
        'v': version,
        'e': epoch,
        't': issuedAt,
        'by': signer,
        'm': [for (final m in members) m.toJson()],
      };

  /// Exactly the bytes the admin signs.
  List<int> signedBytes() =>
      utf8.encode('inventory-sync/v2/members\n${canonicalJson(_body())}');

  String get digest => sha256Hex(signedBytes());

  Map<String, Object?> toJson() => {
        ..._body(),
        if (signature != null) 'sig': b64(signature!),
      };

  static MemberDoc? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final members = <GroupMember>[];
      for (final m in j['m'] as List) {
        final gm = GroupMember.fromJson(m);
        if (gm == null) return null;
        members.add(gm);
      }
      final sig = j['sig'];
      return MemberDoc(
        groupId: j['g'] as String,
        version: (j['v'] as num).toInt(),
        epoch: (j['e'] as num).toInt(),
        issuedAt: (j['t'] as num).toInt(),
        signer: j['by'] as String,
        members: members,
        signature: sig is String ? base64Decode(sig) : null,
      );
    } catch (_) {
      return null;
    }
  }

  MemberDoc next({
    required String signer,
    required int issuedAt,
    required List<GroupMember> members,
    int? epoch,
  }) =>
      MemberDoc(
        groupId: groupId,
        version: version + 1,
        epoch: epoch ?? this.epoch,
        issuedAt: issuedAt,
        signer: signer,
        members: members,
      );

  Future<MemberDoc> signedBy(SyncSigner s) async => MemberDoc(
        groupId: groupId,
        version: version,
        epoch: epoch,
        issuedAt: issuedAt,
        signer: signer,
        members: members,
        signature: await s.sign(signedBytes()),
      );

  Future<bool> verifiedBy(List<int> signKey) async {
    final sig = signature;
    if (sig == null) return false;
    return syncVerify(signedBytes(), signature: sig, publicKey: signKey);
  }

  /// Two admins changed the list at the same moment: everyone keeps the
  /// same one (higher version, then the larger digest).
  bool beats(MemberDoc? other) {
    if (other == null) return true;
    if (version != other.version) return version > other.version;
    return digest.compareTo(other.digest) > 0;
  }
}

enum GroupState { none, joining, active, removed }

/// A device that scanned this admin's invite and waits for Approve.
class GroupJoinCandidate {
  const GroupJoinCandidate({
    required this.deviceId,
    required this.createdAt,
    this.legacyName,
  });
  final String deviceId;
  final DateTime createdAt;

  /// Name this phone already used for it under the old pairing (migration).
  final String? legacyName;
}

/// Deleted by a non-admin device; an admin can put it back.
class SyncTrashEntry {
  const SyncTrashEntry({
    required this.id,
    required this.kind,
    required this.rid,
    required this.title,
    required this.byDevice,
    required this.deletedAt,
  });
  final int id;
  final String kind;
  final String rid;
  final String title;
  final String byDevice;
  final DateTime deletedAt;
}

/// What the Synced Devices page shows about the group.
class GroupInfo {
  const GroupInfo({
    this.state = GroupState.none,
    this.groupId,
    this.myId,
    this.doc,
    this.joins = const [],
    this.trashCount = 0,
    this.lastSyncAt,
  });

  final GroupState state;
  final String? groupId;
  final String? myId;
  final MemberDoc? doc;
  final List<GroupJoinCandidate> joins;
  final int trashCount;
  final DateTime? lastSyncAt;

  GroupMember? get me => myId == null ? null : doc?.member(myId!);
  bool get isAdmin => state == GroupState.active && (me?.isAdmin ?? false);
  List<GroupMember> get activeMembers => doc?.active ?? const [];
  int get adminCount => doc?.admins.length ?? 0;
}

/// A group action the relay or the rules refused. [code]:
/// `invite_invalid`, `already_member`, `in_other_group`, `own_code`,
/// `not_admin`, `last_admin`, `not_pending`, `not_member`.
class GroupError implements Exception {
  const GroupError(this.code);
  final String code;
  @override
  String toString() => 'GroupError($code)';
}
