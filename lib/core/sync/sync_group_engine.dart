part of 'sync_engine.dart';

/// Remote edits stamped further ahead than this wait until their time.
const _kSkewLimitMs = 10 * 60 * 1000;

/// Above this local-vs-relay difference, edit times use the relay's clock.
const _kClockTrustMs = 60 * 1000;
const _kTrashKeepMs = 30 * 24 * 3600 * 1000;
const _kResyncEveryMs = 10 * 60 * 1000;
const _kTrashKinds = {'item', 'sale', 'cust', 'cat'};
const _kInviteTtl = Duration(minutes: 10);
const _kMigrationInviteTtl = Duration(days: 30);

/// v2: one admin-managed group per shop.
///
/// * One mailbox; every message is AES-GCM sealed with the group key of its
///   generation (epoch) and Ed25519-signed by its sender.
/// * The member list is versioned and signed by an admin; only an admin of
///   the list a device already trusts can issue the next one.
/// * Removing a device: relay revokes its token, the list records the
///   mailbox position, and a new key goes to the remaining devices only.
/// * Only admins may forward edits authored by another device; deletions
///   by non-admins land in a 30-day trash on every device.
extension SyncGroups on SyncEngine {
  GroupTransport get _gt {
    final t = _groupTransport;
    if (t == null) throw StateError('relay has no group support');
    return t;
  }

  Future<void> _delMeta(DatabaseExecutor db, String k) =>
      db.delete('sync_meta', where: 'k = ?', whereArgs: [k]);

  Future<int> _metaInt(DatabaseExecutor db, String k) async =>
      int.tryParse(await _meta(db, k) ?? '') ?? 0;

  // ------------------------------------------------------------- identity

  Future<SyncSigner> signer() async {
    final db = await _db();
    final seed = await _meta(db, 'sign_seed');
    final cached = _signer;
    if (cached != null && seed == b64(cached.seed)) return cached;
    final pub = await _meta(db, 'sign_pub');
    if (seed != null && pub != null) {
      final s = SyncSigner(seed: unb64(seed), publicKey: unb64(pub));
      _signer = s;
      return s;
    }
    final fresh = await SyncSigner.generate();
    final saved = await db.transaction((txn) async {
      final s2 = await _meta(txn, 'sign_seed');
      final p2 = await _meta(txn, 'sign_pub');
      if (s2 != null && p2 != null) {
        return SyncSigner(seed: unb64(s2), publicKey: unb64(p2));
      }
      await _setMeta(txn, 'sign_seed', b64(fresh.seed));
      await _setMeta(txn, 'sign_pub', b64(fresh.publicKey));
      return fresh;
    });
    _signer = saved;
    return saved;
  }

  // ---------------------------------------------------------------- state

  Future<GroupState> _gState(DatabaseExecutor db) async =>
      switch (await _meta(db, 'g_state')) {
        'joining' => GroupState.joining,
        'active' => GroupState.active,
        'removed' => GroupState.removed,
        _ => GroupState.none,
      };

  Future<bool> _groupOn(DatabaseExecutor db) async {
    final s = await _gState(db);
    return s == GroupState.active || s == GroupState.joining;
  }

  Future<MemberDoc?> _doc(DatabaseExecutor db) async {
    final j = await _meta(db, 'g_doc');
    return j == null ? null : MemberDoc.fromJson(jsonDecode(j));
  }

  Future<List<Object?>> _docHistory(DatabaseExecutor db) async =>
      jsonDecode(await _meta(db, 'g_docs') ?? '[]') as List;

  Future<void> _storeDoc(DatabaseExecutor db, MemberDoc d) async {
    await _setMeta(db, 'g_doc', jsonEncode(d.toJson()));
    final h = [
      for (final j in await _docHistory(db))
        if (j is Map && j['v'] != d.version) j,
      d.toJson(),
    ];
    if (h.length > 60) h.removeRange(0, h.length - 60);
    await _setMeta(db, 'g_docs', jsonEncode(h));
  }

  Future<Map<int, Uint8List>> _keys(DatabaseExecutor db) async => {
        for (final r in await db.query('sync_group_keys'))
          r['epoch']! as int: unb64(r['k']! as String),
      };

  Future<void> _addKey(DatabaseExecutor db, int epoch, Uint8List key) =>
      db.insert(
        'sync_group_keys',
        {'epoch': epoch, 'k': b64(key)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// Generation numbers carry a random part so two admins rotating at the
  /// same moment never hand out two different keys under one number.
  int _newEpoch(int version) {
    final r = syncRandomBytes(2);
    return version * 1000 + ((r[0] << 8) | r[1]) % 1000;
  }

  Future<GroupAuth?> _auth(DatabaseExecutor db) async {
    final g = await _meta(db, 'g_id');
    final t = await _meta(db, 'g_token');
    if (g == null || t == null) return null;
    return GroupAuth(
      groupId: g,
      deviceId: (await identity()).deviceId,
      token: t,
    );
  }

  Future<GroupAuth> _authOrThrow(DatabaseExecutor db) async =>
      await _auth(db) ?? (throw const GroupError('not_member'));

  /// Forget keys and group state (shop data and sync history stay).
  Future<void> _clearGroupLocal(DatabaseExecutor db, {String? state}) async {
    for (final t in ['sync_group_keys', 'sync_joins', 'sync_deferred']) {
      await db.delete(t);
    }
    if (state != 'removed') await db.delete('sync_trash');
    for (final k in [
      'g_token', 'g_doc', 'g_docs', 'g_cursor', 'g_pushed', 'g_dump',
      'g_invite', 'g_outbox', 'g_resync_at', 'g_last_ok', 'g_auto',
    ]) {
      await _delMeta(db, k);
    }
    if (state == null) {
      await _delMeta(db, 'g_state');
      await _delMeta(db, 'g_id');
    } else {
      await _setMeta(db, 'g_state', state);
    }
  }

  Future<void> _becomeRemoved(DatabaseExecutor db) async {
    await _clearGroupLocal(db, state: 'removed');
    await db.delete('sync_trash');
  }

  Future<GroupInfo> groupInfo() async {
    final db = await _db();
    final me = await identity();
    final st = await _gState(db);
    final doc = await _doc(db);
    final joins = st == GroupState.active
        ? [
            for (final r in await db.query('sync_joins', orderBy: 'created_at'))
              GroupJoinCandidate(
                deviceId: r['device_id']! as String,
                legacyName: r['legacy_name'] as String?,
                createdAt:
                    DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
              ),
          ]
        : const <GroupJoinCandidate>[];
    final trash = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sync_trash'),
        ) ??
        0;
    final last = await _metaInt(db, 'g_last_ok');
    return GroupInfo(
      state: st,
      groupId: await _meta(db, 'g_id'),
      myId: me.deviceId,
      doc: doc,
      joins: joins,
      trashCount: trash,
      lastSyncAt: last == 0 ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  /// One-shot flag: the admin declined this device's join request.
  Future<bool> takeJoinDeclined() async {
    final db = await _db();
    final v = await _meta(db, 'g_declined');
    if (v == null) return false;
    await _delMeta(db, 'g_declined');
    return true;
  }

  // ------------------------------------------------------------ messages

  /// Sealed group message. Group-wide messages carry one HMAC tag per
  /// active member, keyed by X25519(sender, member): every member can check
  /// who sent it, nobody else (other members, removed devices, the relay)
  /// can forge it. (Per-message Ed25519 costs ~0.5 s in pure Dart; the
  /// admin-signed member list keeps Ed25519.) Direct messages are
  /// authenticated by their pairwise AES-GCM key.
  Future<GroupItem> _seal(
    Map<String, Object?> msg, {
    required String gid,
    required int epoch,
    required Uint8List key,
    String? to,
    List<GroupMember> recipients = const [],
  }) async {
    final me = await identity();
    final body = gzip.encode(utf8.encode(jsonEncode({
      ...msg,
      'v': 2,
      'f': me.deviceId,
      't': _now,
    })));
    final head = '$gid|${me.deviceId}|${to ?? ''}|$epoch';
    final digest = [...utf8.encode('$head\n'), ...sha256Bytes(body)];
    final tags = <int>[];
    var n = 0;
    if (to == null) {
      for (final m in recipients) {
        if (m.deviceId == me.deviceId || !m.isActive) continue;
        final mk = await _pairKey(gid, m.deviceId, m.publicKey, 'mac');
        tags
          ..addAll(sha256Bytes(utf8.encode(m.deviceId)).sublist(0, 8))
          ..addAll(await hmacSha256(mk, digest));
        n++;
      }
    }
    final clear = Uint8List.fromList([3, n >> 8, n & 0xff, ...tags, ...body]);
    return GroupItem(
      blob: await sealBytes(clear, key: key, aad: head),
      epoch: epoch,
      to: to,
    );
  }

  Future<Map<String, Object?>?> _open(
    GroupItem it, {
    required String gid,
    required Uint8List key,
    required Uint8List senderX,
  }) async {
    final head = '$gid|${it.sender}|${it.to ?? ''}|${it.epoch}';
    try {
      final clear = await openBytes(it.blob, key: key, aad: head);
      if (clear.length < 3 || clear[0] != 3) return null;
      final n = (clear[1] << 8) | clear[2];
      final start = 3 + n * 40;
      if (clear.length < start) return null;
      final body = clear.sublist(start);
      if (it.to == null) {
        final me = (await identity()).deviceId;
        final myTag = sha256Bytes(utf8.encode(me)).sublist(0, 8);
        Uint8List? mac;
        for (var i = 0; i < n; i++) {
          final o = 3 + i * 40;
          if (constantTimeEq(clear.sublist(o, o + 8), myTag)) {
            mac = clear.sublist(o + 8, o + 40);
            break;
          }
        }
        if (mac == null) return null; // sealed before this device joined
        final mk = await _pairKey(gid, it.sender, senderX, 'mac');
        final want = await hmacSha256(
          mk,
          [...utf8.encode('$head\n'), ...sha256Bytes(body)],
        );
        if (!constantTimeEq(mac, want)) return null;
      }
      final m = jsonDecode(utf8.decode(gzip.decode(body)));
      if (m is! Map<String, Object?> || m['f'] != it.sender) return null;
      return m;
    } catch (_) {
      return null; // not ours / tampered — skip, never touch data
    }
  }

  Future<Uint8List> _pairKey(
    String gid,
    String peerId,
    Uint8List peerX,
    String purpose,
  ) async {
    final id = '$gid|$peerId|${b64(peerX)}|$purpose';
    final hit = _pairKeyCache[id];
    if (hit != null) return hit;
    final k = await deriveDirectKey(
      me: await identity(),
      peerId: peerId,
      peerPublicKey: peerX,
      groupId: gid,
      purpose: purpose,
    );
    return _pairKeyCache[id] = k;
  }

  Future<Uint8List> _directKey(String gid, String peerId, Uint8List peerX) =>
      _pairKey(gid, peerId, peerX, 'direct');

  /// Control messages wait here until the relay has them (survives offline).
  Future<void> _queue(
    DatabaseExecutor db,
    Map<String, Object?> msg, {
    String? to,
  }) async {
    final list = jsonDecode(await _meta(db, 'g_outbox') ?? '[]') as List;
    list.add({'to': to, 'msg': msg});
    await _setMeta(db, 'g_outbox', jsonEncode(list));
  }

  Future<void> _flushOutbox(DatabaseExecutor db, GroupAuth auth) async {
    final list = jsonDecode(await _meta(db, 'g_outbox') ?? '[]') as List;
    if (list.isEmpty) return;
    final doc = await _doc(db);
    final keys = await _keys(db);
    final items = <GroupItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final msg = (e['msg'] as Map).cast<String, Object?>();
      final to = e['to'] as String?;
      if (to != null) {
        final m = doc?.member(to);
        if (m == null) continue;
        items.add(await _seal(
          msg,
          gid: auth.groupId,
          epoch: 0,
          key: await _directKey(auth.groupId, to, m.publicKey),
          to: to,
        ));
      } else {
        final key = doc == null ? null : keys[doc.epoch];
        if (key == null) continue;
        items.add(await _seal(msg,
            gid: auth.groupId, epoch: doc!.epoch, key: key, recipients: doc.members));
      }
    }
    if (items.isNotEmpty) await _gt.pushGroup(auth, items);
    // Only drop what was sent (an action may have queued more meanwhile).
    final now = jsonDecode(await _meta(db, 'g_outbox') ?? '[]') as List;
    final rest = now.length > list.length ? now.sublist(list.length) : const [];
    if (rest.isEmpty) {
      await _delMeta(db, 'g_outbox');
    } else {
      await _setMeta(db, 'g_outbox', jsonEncode(rest));
    }
  }

  Future<void> _tryFlush(DatabaseExecutor db) async {
    final auth = await _auth(db);
    if (auth == null) return;
    try {
      await _flushOutbox(db, auth);
    } catch (_) {
      // Offline: the next sync run sends it.
    }
  }

  // -------------------------------------------------------- member lists

  /// Accept newer lists, each signed by an admin of the list held before it.
  /// [anchor*]: the admin whose invite this device scanned (first list only).
  Future<bool> _acceptDocs(
    DatabaseExecutor db,
    List<MemberDoc?> docs, {
    String? anchorId,
    Uint8List? anchorSignKey,
  }) async {
    final gid = await _meta(db, 'g_id');
    var cur = await _doc(db);
    final sorted = [
      for (final d in docs)
        if (d != null && d.groupId == gid) d,
    ]..sort((a, b) => a.version.compareTo(b.version));
    if (cur == null && anchorId != null) {
      // First list: the admin whose QR was scanned vouches for it.
      final mine = sorted.where((d) => d.signer == anchorId).toList();
      sorted
        ..clear()
        ..addAll(mine.isEmpty ? const [] : [mine.last]);
    }
    var ok = true, changed = false;
    for (final d in sorted) {
      if (cur != null && !d.beats(cur)) continue;
      Uint8List? signKey;
      if (cur != null) {
        final s = cur.member(d.signer);
        if (s != null && s.isAdmin) signKey = s.signKey;
      } else if (anchorId != null && d.signer == anchorId) {
        signKey = anchorSignKey;
      }
      if (signKey == null || d.admins.isEmpty || !await d.verifiedBy(signKey)) {
        ok = false;
        continue;
      }
      cur = d;
      changed = true;
      await _storeDoc(db, d);
    }
    if (changed) await _afterDocChange(db, cur!);
    return ok;
  }

  Future<void> _afterDocChange(DatabaseExecutor db, MemberDoc doc) async {
    final me = (await identity()).deviceId;
    final mine = doc.member(me);
    if (await _gState(db) != GroupState.active) return;
    if (mine == null || !mine.isActive) {
      await _becomeRemoved(db);
      return;
    }
    if (!mine.isAdmin) {
      await db.delete('sync_joins');
    } else {
      for (final m in doc.active) {
        await db.delete('sync_joins', where: 'device_id = ?', whereArgs: [m.deviceId]);
      }
    }
  }

  /// Call [identity] and [signer] BEFORE a transaction (they read the
  /// database outside it; inside one, sqflite would wait forever).
  Future<MemberDoc> _issueDoc(
    DatabaseExecutor db,
    MemberDoc cur,
    List<GroupMember> members, {
    required String me,
    required SyncSigner sg,
    int? epoch,
  }) async {
    final next = await cur
        .next(signer: me, issuedAt: _now, members: members, epoch: epoch)
        .signedBy(sg);
    await _storeDoc(db, next);
    return next;
  }

  Future<({MemberDoc doc, GroupAuth auth, String me})> _asAdmin(
    DatabaseExecutor db,
  ) async {
    final doc = await _doc(db);
    final me = (await identity()).deviceId;
    if (await _gState(db) != GroupState.active ||
        doc == null ||
        !(doc.member(me)?.isAdmin ?? false)) {
      throw const GroupError('not_admin');
    }
    await signer(); // cached for _issueDoc inside transactions
    return (doc: doc, auth: await _authOrThrow(db), me: me);
  }

  /// The relay answers 404 `not_found` for any /v2 route until the group
  /// server update is deployed (ids we send are always well-formed).
  bool _v2Missing(SyncServerException e) =>
      e.status == 404 && (e.message == 'not_found' || e.message == 'bad response');

  Never _serverError(SyncServerException e) {
    final m = e.message;
    if (m == 'last_admin') throw const GroupError('last_admin');
    if (m == 'not_admin' || e.status == 403) throw const GroupError('not_admin');
    if (m == 'not_pending') throw const GroupError('not_pending');
    if (m == 'already_member') throw const GroupError('already_member');
    if (m == 'not_member') throw const GroupError('not_member');
    throw e;
  }

  // ------------------------------------------------------------- actions

  /// This device starts the shop's group and becomes its first admin.
  /// Devices paired the old way get an invite automatically; each needs one
  /// Approve here.
  Future<void> createGroup() async {
    final db = await _db();
    final me = await identity();
    final sg = await signer();
    if (await _groupOn(db)) throw const GroupError('in_other_group');
    final gid = b64url(syncRandomBytes(18));
    final token = b64url(syncRandomBytes(32));
    try {
      await _gt.createGroup(
        GroupAuth(groupId: gid, deviceId: me.deviceId, token: token),
        publicKey: b64(me.publicKey),
      );
    } on SyncServerException catch (e) {
      if (_v2Missing(e)) throw const GroupError('server_update');
      rethrow;
    }
    final now = _now;
    final epoch = _newEpoch(1);
    final doc = await MemberDoc(
      groupId: gid,
      version: 1,
      epoch: epoch,
      issuedAt: now,
      signer: me.deviceId,
      members: [
        GroupMember(
          deviceId: me.deviceId,
          name: '',
          role: 'admin',
          status: 'active',
          publicKey: me.publicKey,
          signKey: sg.publicKey,
          addedAt: now,
        ),
      ],
    ).signedBy(sg);
    final maxLseq = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COALESCE(MAX(lseq), 0) FROM sync_records'),
        ) ??
        0;
    await db.transaction((txn) async {
      await _clearGroupLocal(txn, state: 'active');
      await _setMeta(txn, 'g_id', gid);
      await _setMeta(txn, 'g_token', token);
      await _setMeta(txn, 'g_cursor', '0');
      // Nobody else is in the group yet; each newcomer gets a full copy.
      await _setMeta(txn, 'g_pushed', '$maxLseq');
      await _addKey(txn, epoch, syncRandomBytes(32));
      await _storeDoc(txn, doc);
      await txn.delete('sync_meta', where: "k LIKE 'ginv_%'");
    });
  }

  /// One-time invite QR (admin only), valid for [ttl].
  Future<String> createInvite({Duration ttl = _kInviteTtl}) async {
    final db = await _db();
    final a = await _asAdmin(db);
    final me = await identity();
    final secret = b64url(syncRandomBytes(18));
    try {
      await _gt.addInvite(
        a.auth,
        secretHash: sha256Hex(utf8.encode(secret)),
        expiresAt: _now + ttl.inMilliseconds,
      );
    } on SyncServerException catch (e) {
      if (_v2Missing(e)) throw const GroupError('server_update');
      _serverError(e);
    }
    return GroupInvitePayload(
      groupId: a.auth.groupId,
      adminId: me.deviceId,
      adminKey: me.publicKey,
      adminSignKey: (await signer()).publicKey,
      secret: secret,
    ).encode();
  }

  /// Newcomer: send a join request sealed to the admin whose QR was
  /// scanned. Syncing starts once that admin (or another) taps Approve.
  Future<void> joinGroup(GroupInvitePayload inv) async {
    final db = await _db();
    final me = await identity();
    final sg = await signer();
    if (inv.adminId == me.deviceId) throw const GroupError('own_code');
    final st = await _gState(db);
    if (st == GroupState.active) {
      throw GroupError(
        await _meta(db, 'g_id') == inv.groupId ? 'already_member' : 'in_other_group',
      );
    }
    final token = b64url(syncRandomBytes(32));
    final auth = GroupAuth(groupId: inv.groupId, deviceId: me.deviceId, token: token);
    final key = await _directKey(inv.groupId, inv.adminId, inv.adminKey);
    final req = await sealBytes(
      utf8.encode(jsonEncode({
        'd': me.deviceId,
        's': b64(sg.publicKey),
        'g': inv.groupId,
      })),
      key: key,
      aad: '${inv.groupId}|join|${me.deviceId}',
    );
    try {
      await _gt.join(
        auth,
        secret: inv.secret,
        publicKey: b64(me.publicKey),
        request: req,
      );
    } on SyncServerException catch (e) {
      if (_v2Missing(e)) throw const GroupError('server_update');
      throw GroupError(e.status == 409 ? 'already_member' : 'invite_invalid');
    }
    await db.transaction((txn) async {
      await _clearGroupLocal(txn, state: 'joining');
      await _delMeta(txn, 'g_declined');
      await _setMeta(txn, 'g_id', inv.groupId);
      await _setMeta(txn, 'g_token', token);
      await _setMeta(txn, 'g_cursor', '0');
      await _setMeta(
        txn,
        'g_invite',
        jsonEncode({
          'd': inv.adminId,
          'x': b64(inv.adminKey),
          's': b64(inv.adminSignKey),
        }),
      );
    });
  }

  Future<void> cancelJoin() async {
    final db = await _db();
    final auth = await _auth(db);
    if (auth != null) {
      try {
        await _gt.leave(auth);
      } catch (_) {}
    }
    await _clearGroupLocal(db);
  }

  /// Admin: let a scanned device in, under [name]. It receives the group
  /// key and member list end-to-end encrypted, then a full copy of the shop.
  Future<void> approveJoin(
    String deviceId,
    String name, {
    bool asAdmin = false,
  }) async {
    final db = await _db();
    final a = await _asAdmin(db);
    final rows = await db.query(
      'sync_joins',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    if (rows.isEmpty) throw const GroupError('not_pending');
    final role = asAdmin ? 'admin' : 'member';
    try {
      await _gt.approve(a.auth, deviceId, role: role);
    } on SyncServerException catch (e) {
      _serverError(e);
    }
    final member = GroupMember(
      deviceId: deviceId,
      name: name.trim().isEmpty ? 'Device' : name.trim(),
      role: role,
      status: 'active',
      publicKey: unb64(rows.first['public_key']! as String),
      signKey: unb64(rows.first['sign_key']! as String),
      addedAt: _now,
    );
    await db.transaction((txn) async {
      final next = await _issueDoc(txn, a.doc, me: a.me, sg: _signer!, [
        for (final m in a.doc.members)
          if (m.deviceId != deviceId) m,
        member,
      ]);
      final key = (await _keys(txn))[next.epoch]!;
      await txn.delete('sync_joins', where: 'device_id = ?', whereArgs: [deviceId]);
      await _queue(txn, {'m': 'mem', 'doc': next.toJson()});
      await _queue(txn, {
        'm': 'key',
        'keys': {'${next.epoch}': b64(key)},
        'docs': await _docHistory(txn),
      }, to: deviceId);
      // Full copy of the shop for the newcomer.
      await _setMeta(txn, 'g_pushed', '0');
      await _setMeta(txn, 'g_dump', '1');
    });
    await _dropLegacy(db, deviceId);
    await _tryFlush(db);
  }

  Future<void> rejectJoin(String deviceId) async {
    final db = await _db();
    final a = await _asAdmin(db);
    try {
      await _gt.reject(a.auth, deviceId);
    } on SyncServerException catch (e) {
      _serverError(e);
    }
    await db.delete('sync_joins', where: 'device_id = ?', whereArgs: [deviceId]);
  }

  /// Admin: remove a device. The relay revokes it at once, the member list
  /// records where its writes end, and a new group key reaches every other
  /// device (never the removed one). Its data stays on its own phone.
  Future<void> removeMember(String deviceId) async {
    final db = await _db();
    final a = await _asAdmin(db);
    if (deviceId == a.me) throw const GroupError('not_member');
    final target = a.doc.member(deviceId);
    if (target == null || !target.isActive) throw const GroupError('not_member');
    int seq;
    try {
      seq = await _gt.revoke(a.auth, deviceId);
    } on SyncServerException catch (e) {
      _serverError(e);
    }
    final epoch = _newEpoch(a.doc.version + 1);
    final key = syncRandomBytes(32);
    await db.transaction((txn) async {
      await _addKey(txn, epoch, key);
      final next = await _issueDoc(
        txn,
        a.doc,
        me: a.me,
        sg: _signer!,
        [
          for (final m in a.doc.members)
            m.deviceId == deviceId
                ? m.copyWith(status: 'removed', removedAt: _now, removedSeq: seq)
                : m,
        ],
        epoch: epoch,
      );
      final history = await _docHistory(txn);
      for (final m in next.active) {
        if (m.deviceId == a.me) continue;
        await _queue(txn, {
          'm': 'key',
          'keys': {'$epoch': b64(key)},
          'docs': history,
        }, to: m.deviceId);
      }
      await _queue(txn, {'m': 'mem', 'doc': next.toJson()});
      await txn.delete('sync_joins', where: 'device_id = ?', whereArgs: [deviceId]);
    });
    await _dropLegacy(db, deviceId);
    await _tryFlush(db);
  }

  /// Admin: make a device admin, or back to a normal device. The last admin
  /// can not be demoted (relay and app both refuse).
  Future<void> setMemberRole(String deviceId, {required bool admin}) async {
    final db = await _db();
    final a = await _asAdmin(db);
    final target = a.doc.member(deviceId);
    if (target == null || !target.isActive) throw const GroupError('not_member');
    if (target.isAdmin == admin) return;
    if (!admin && a.doc.admins.length <= 1) throw const GroupError('last_admin');
    try {
      await _gt.setRole(a.auth, deviceId, admin ? 'admin' : 'member');
    } on SyncServerException catch (e) {
      _serverError(e);
    }
    await db.transaction((txn) async {
      final next = await _issueDoc(txn, a.doc, me: a.me, sg: _signer!, [
        for (final m in a.doc.members)
          m.deviceId == deviceId ? m.copyWith(role: admin ? 'admin' : 'member') : m,
      ]);
      await _queue(txn, {'m': 'mem', 'doc': next.toJson()});
    });
    await _tryFlush(db);
  }

  /// Admin: rename a device for everyone.
  Future<void> renameMember(String deviceId, String name) async {
    final db = await _db();
    final a = await _asAdmin(db);
    final clean = name.trim();
    if (clean.isEmpty || a.doc.member(deviceId) == null) return;
    await db.transaction((txn) async {
      final next = await _issueDoc(txn, a.doc, me: a.me, sg: _signer!, [
        for (final m in a.doc.members)
          m.deviceId == deviceId ? m.copyWith(name: clean) : m,
      ]);
      await _queue(txn, {'m': 'mem', 'doc': next.toJson()});
    });
    await _tryFlush(db);
  }

  /// This device leaves the group (local data stays). An admin can only
  /// leave while another admin remains.
  Future<void> leaveGroup() async {
    final db = await _db();
    final auth = await _auth(db);
    final doc = await _doc(db);
    final me = (await identity()).deviceId;
    if (auth != null && await _gState(db) == GroupState.active) {
      final mine = doc?.member(me);
      if (mine != null &&
          mine.isAdmin &&
          doc!.admins.length <= 1 &&
          doc.active.length > 1) {
        throw const GroupError('last_admin');
      }
      // Tell the admins first so they rotate the key without this device.
      await _queue(db, {'m': 'bye'});
      await _flushOutbox(db, auth);
      try {
        await _gt.leave(auth);
      } on SyncServerException catch (e) {
        if (e.status != 410) _serverError(e);
      }
    }
    await _clearGroupLocal(db);
  }

  /// Admin: delete the shop group. The relay revokes every other device at
  /// once (they stop syncing and show "removed"; their data stays on them),
  /// open join requests are dropped, then this device leaves too. Its own
  /// data stays. Safe to retry after a network error: revoking twice is a
  /// no-op on the relay, and local state is only cleared at the end.
  Future<void> dissolveGroup() async {
    final db = await _db();
    final a = await _asAdmin(db);
    try {
      for (final m in a.doc.active) {
        if (m.deviceId == a.me) continue;
        await _gt.revoke(a.auth, m.deviceId);
      }
      for (final r in await db.query('sync_joins', columns: ['device_id'])) {
        try {
          await _gt.reject(a.auth, r['device_id']! as String);
        } on SyncServerException catch (_) {}
      }
      await _gt.leave(a.auth);
    } on SyncServerException catch (e) {
      if (e.status != 410) _serverError(e);
    }
    // Devices still paired the old way go too: nothing keeps syncing.
    for (final r in await db.query('sync_peers', columns: ['peer_id'])) {
      await _dropLegacy(db, r['peer_id']! as String);
    }
    await _clearGroupLocal(db);
  }

  // ---------------------------------------------------------------- trash

  Future<List<SyncTrashEntry>> trash() async {
    final db = await _db();
    return [
      for (final r in await db.query('sync_trash', orderBy: 'deleted_at DESC'))
        SyncTrashEntry(
          id: r['id']! as int,
          kind: r['kind']! as String,
          rid: r['rid']! as String,
          title: r['title']! as String,
          byDevice: r['by_device']! as String,
          deletedAt: DateTime.fromMillisecondsSinceEpoch(r['deleted_at']! as int),
        ),
    ];
  }

  static String _trashTitle(String kind, String rid, Object? data) {
    Map<Object?, Object?> m = data is Map ? data : const {};
    switch (kind) {
      case 'item':
        return '${m['title'] ?? ''}';
      case 'cat':
        return '${m['name'] ?? ''}';
      case 'cust':
        return '${m['name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      case 'sale':
        m = m['s'] is Map ? m['s']! as Map : const {};
        final id = '${m['id'] ?? rid}';
        return '#${(id.length > 8 ? id.substring(0, 8) : id).toUpperCase()}';
    }
    return rid;
  }

  Future<void> _toTrash(DatabaseExecutor db, SyncChange c) async {
    final data = await _payloadFor(db, c.kind, c.rid);
    if (data == null) return;
    // Links the delete cuts: put them back on restore.
    List<Object?> linked = const [];
    if (c.kind == 'cat') {
      linked = [
        for (final r in await db.query('inventory_items',
            columns: ['id'], where: 'category_id = ?', whereArgs: [c.rid]))
          r['id'],
      ];
    } else if (c.kind == 'cust') {
      linked = [
        for (final r in await db.query('sales',
            columns: ['id'], where: 'customer_id = ?', whereArgs: [c.rid]))
          r['id'],
      ];
    }
    await db.insert('sync_trash', {
      'kind': c.kind,
      'rid': c.rid,
      'title': _trashTitle(c.kind, c.rid, data),
      'data': jsonEncode({'d': data, 'l': linked}),
      'by_device': c.origin,
      'deleted_at': _now,
    });
  }

  /// Admin: put deleted records back. They sync to every device as a new
  /// edit. Returns how many came back.
  Future<int> restoreTrash(List<int> ids) async {
    final db = await _db();
    var n = 0;
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        for (final id in ids) {
          final r = await txn.query('sync_trash', where: 'id = ?', whereArgs: [id]);
          if (r.isEmpty) continue;
          final kind = r.first['kind']! as String;
          final rid = r.first['rid']! as String;
          final j = jsonDecode(r.first['data']! as String) as Map;
          await _applyOne(
            txn,
            SyncChange(kind: kind, rid: rid, ts: 0, origin: '', deleted: false, data: j['d']),
          );
          final linked = (j['l'] as List? ?? const []).whereType<String>().toList();
          for (final l in linked) {
            if (kind == 'cat') {
              await txn.update('inventory_items', {'category_id': rid},
                  where: 'id = ? AND category_id IS NULL', whereArgs: [l]);
            } else if (kind == 'cust') {
              await txn.update('sales', {'customer_id': rid},
                  where: 'id = ? AND customer_id IS NULL', whereArgs: [l]);
            }
          }
          await txn.delete('sync_trash', where: 'id = ?', whereArgs: [id]);
          n++;
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
    return n;
  }

  Future<void> emptyTrash([List<int>? ids]) async {
    final db = await _db();
    if (ids == null) {
      await db.delete('sync_trash');
      return;
    }
    for (final id in ids) {
      await db.delete('sync_trash', where: 'id = ?', whereArgs: [id]);
    }
  }

  // -------------------------------------------------------------- legacy

  Future<void> _dropLegacy(DatabaseExecutor db, String peerId) async {
    final rows = await db.query('sync_peers', where: 'peer_id = ?', whereArgs: [peerId]);
    if (rows.isEmpty) return;
    try {
      await transport.drop(
        pairId: rows.first['pair_id']! as String,
        auth: rows.first['auth']! as String,
      );
    } catch (_) {}
    await db.delete('sync_peers', where: 'peer_id = ?', whereArgs: [peerId]);
    await _delMeta(db, 'ginv_$peerId');
  }

  /// Migration: an admin sends each device it was paired with the old way
  /// a personal invite through that (still encrypted) pair.
  Future<void> _maybeInviteLegacy(Database db, Map<String, Object?> peer) async {
    if (peer['status'] != 'active' || await _gState(db) != GroupState.active) return;
    final peerId = peer['peer_id']! as String;
    if (await _meta(db, 'ginv_$peerId') != null) return;
    final doc = await _doc(db);
    final me = await identity();
    if (doc == null || !(doc.member(me.deviceId)?.isAdmin ?? false)) return;
    if (doc.member(peerId)?.isActive ?? false) return;
    final code = await createInvite(ttl: _kMigrationInviteTtl);
    final msg = await SyncEngine.sealMessage(
      {'v': 1, 'f': me.deviceId, 'm': 'ginv', 'i': code},
      key: unb64(peer['enc_key']! as String),
      pairId: peer['pair_id']! as String,
    );
    await transport.push(
      pairId: peer['pair_id']! as String,
      auth: peer['auth']! as String,
      sender: me.deviceId,
      blobs: [msg],
    );
    await _setMeta(db, 'ginv_$peerId', '1');
  }

  /// An old-style paired device started a group: ask to join it (its admin
  /// approves once). Two devices that both started one alone: the group
  /// with the smaller id wins on both.
  Future<void> _onLegacyInvite(DatabaseExecutor db, Object? code) async {
    final inv = GroupInvitePayload.tryParse(code is String ? code : null);
    if (inv == null) return;
    final st = await _gState(db);
    final gid = await _meta(db, 'g_id');
    if (st == GroupState.joining) return;
    if (st == GroupState.active) {
      if (gid == inv.groupId) return;
      final doc = await _doc(db);
      if (doc == null || doc.active.length > 1) return;
      if (inv.groupId.compareTo(gid!) >= 0) return;
      final auth = await _auth(db);
      if (auth != null) {
        try {
          await _gt.leave(auth);
        } catch (_) {}
      }
      await _clearGroupLocal(db);
    }
    try {
      await joinGroup(inv);
      await _setMeta(db, 'g_auto', '1');
    } catch (_) {
      // Offline or invite used: the admin's QR still works.
    }
  }

  // ------------------------------------------------------------------ run

  void _noteServerTime(int serverNow) {
    if (serverNow <= 0) return;
    final off = serverNow - _clock().millisecondsSinceEpoch;
    _clockOffset = off.abs() > _kClockTrustMs ? off : 0;
  }

  Future<int> _applyDeferred(Database db) async {
    final rows = await db.query(
      'sync_deferred',
      where: 'ts <= ?',
      whereArgs: [_now + _kSkewLimitMs],
      orderBy: 'id',
    );
    if (rows.isEmpty) return 0;
    final doc = await _doc(db);
    var n = 0;
    for (final r in rows) {
      final c = SyncChange.fromJson(jsonDecode(r['change']! as String));
      await db.delete('sync_deferred', where: 'id = ?', whereArgs: [r['id']]);
      if (c == null) continue;
      n += await applyRemote(
        [c],
        src: r['src']! as String,
        trashIf: (c) => !(doc?.member(c.origin)?.isAdmin ?? false),
      );
    }
    return n;
  }

  Future<void> _askResync(DatabaseExecutor db) async {
    final last = await _metaInt(db, 'g_resync_at');
    if (_now - last < _kResyncEveryMs) return;
    await _setMeta(db, 'g_resync_at', '$_now');
    await _queue(db, {'m': 'resync'});
  }

  Future<int> _groupPull(Database db, GroupAuth auth) async {
    final me = (await identity()).deviceId;
    var after = await _metaInt(db, 'g_cursor');
    var applied = 0;
    var missing = false;
    for (var page = 0; page < 20; page++) {
      final res = await _gt.pullGroup(auth, after: after);
      _noteServerTime(res.serverNow);
      if (res.status != 'active') return applied;
      if (res.gap) missing = true;
      for (final it in res.items) {
        applied += await _handleItem(db, it, me, () => missing = true);
        after = it.seq;
        await _setMeta(db, 'g_cursor', '$after');
        if (!await _groupOn(db)) return applied;
      }
      if (!res.more || res.items.isEmpty) break;
    }
    if (missing && await _gState(db) == GroupState.active) await _askResync(db);
    return applied;
  }

  Future<int> _handleItem(
    Database db,
    GroupItem it,
    String me,
    void Function() missing,
  ) async {
    final st = await _gState(db);
    final gid = await _meta(db, 'g_id');
    if (gid == null) return 0;
    final doc = await _doc(db);
    if (it.to != null) {
      if (it.to != me) return 0;
      Uint8List? x, s;
      final m = doc?.member(it.sender);
      Map<String, Object?>? inv;
      if (st == GroupState.joining) {
        inv = (jsonDecode(await _meta(db, 'g_invite') ?? '{}') as Map).cast();
      }
      if (m != null) {
        x = m.publicKey;
        s = m.signKey;
      } else if (inv != null && inv['d'] == it.sender) {
        x = unb64(inv['x']! as String);
        s = unb64(inv['s']! as String);
      }
      if (x == null || s == null) return 0;
      final msg = await _open(
        it,
        gid: gid,
        key: await _directKey(gid, it.sender, x),
        senderX: x,
      );
      if (msg != null && msg['m'] == 'key') {
        await _onKeyMsg(db, it.sender, msg, inv);
      }
      return 0;
    }
    if (st != GroupState.active || doc == null) return 0;
    final sender = doc.member(it.sender);
    if (sender == null) {
      missing();
      return 0;
    }
    // A removed device: only what it wrote before the removal counts.
    if (!sender.isActive &&
        (sender.removedSeq == null || it.seq > sender.removedSeq!)) {
      return 0;
    }
    final key = (await _keys(db))[it.epoch];
    if (key == null) {
      missing();
      return 0;
    }
    final msg = await _open(it, gid: gid, key: key, senderX: sender.publicKey);
    if (msg == null) {
      // Sealed before this device was in the list: an admin re-sends.
      missing();
      return 0;
    }
    switch (msg['m']) {
      case 'mem':
        if (!await _acceptDocs(db, [MemberDoc.fromJson(msg['doc'])])) missing();
        return 0;
      case 'chg':
        return _onChanges(db, sender, doc, msg);
      case 'resync':
        await _onResync(db, sender, doc);
        return 0;
      case 'bye':
        await _onBye(db, sender, doc);
        return 0;
    }
    return 0;
  }

  Future<void> _onKeyMsg(
    Database db,
    String sender,
    Map<String, Object?> msg,
    Map<String, Object?>? invite,
  ) async {
    final st = await _gState(db);
    final docs = [
      for (final j in (msg['docs'] as List? ?? const [])) MemberDoc.fromJson(j),
    ];
    if (st == GroupState.joining && invite != null) {
      await _acceptDocs(
        db,
        docs,
        anchorId: invite['d'] as String?,
        anchorSignKey: unb64(invite['s']! as String),
      );
    } else {
      await _acceptDocs(db, docs);
    }
    final doc = await _doc(db);
    if (doc == null) return;
    // Only an admin of the trusted list hands out keys.
    if (!(doc.member(sender)?.isAdmin ?? false)) return;
    final keys = msg['keys'];
    if (keys is Map) {
      for (final e in keys.entries) {
        final epoch = int.tryParse('${e.key}');
        final k = e.value;
        if (epoch == null || k is! String) continue;
        final raw = unb64(k);
        if (raw.length == 32) await _addKey(db, epoch, raw);
      }
    }
    final me = (await identity()).deviceId;
    if (st == GroupState.joining &&
        (doc.member(me)?.isActive ?? false) &&
        (await _keys(db)).containsKey(doc.epoch)) {
      await _setMeta(db, 'g_state', 'active');
      await _delMeta(db, 'g_invite');
      // Send this device's own records once (others already have the rest).
      await _setMeta(db, 'g_pushed', '0');
      // Old-style pairs end here; the group replaces them.
      for (final p in await db.query('sync_peers')) {
        await _dropLegacy(db, p['peer_id']! as String);
      }
    }
  }

  Future<int> _onChanges(
    Database db,
    GroupMember sender,
    MemberDoc doc,
    Map<String, Object?> msg,
  ) async {
    final now = _now;
    final ok = <SyncChange>[];
    for (final raw in (msg['c'] as List? ?? const [])) {
      final c = SyncChange.fromJson(raw);
      if (c == null) continue;
      // Only admins may forward edits authored by another device.
      if (c.origin != sender.deviceId && !sender.isAdmin) continue;
      final author = doc.member(c.origin);
      if (author != null &&
          !author.isActive &&
          author.removedAt != null &&
          c.ts > author.removedAt!) {
        continue;
      }
      if (c.ts > now + _kSkewLimitMs) {
        await db.insert('sync_deferred', {
          'ts': c.ts - _kSkewLimitMs,
          'src': 'g:${sender.deviceId}',
          'change': jsonEncode(c.toJson()),
        });
        continue;
      }
      ok.add(c);
    }
    return applyRemote(
      ok,
      src: 'g:${sender.deviceId}',
      trashIf: (c) => !(doc.member(c.origin)?.isAdmin ?? false),
    );
  }

  Future<void> _onResync(
    DatabaseExecutor db,
    GroupMember sender,
    MemberDoc doc,
  ) async {
    if (!sender.isActive) return;
    final me = doc.member((await identity()).deviceId);
    if (me == null || !me.isActive) return;
    final last = _resyncServed[sender.deviceId] ?? 0;
    if (_now - last < 5 * 60 * 1000) return;
    _resyncServed[sender.deviceId] = _now;
    if (me.isAdmin) {
      await _queue(db, {
        'm': 'key',
        'keys': {
          for (final e in (await _keys(db)).entries) '${e.key}': b64(e.value),
        },
        'docs': await _docHistory(db),
      }, to: sender.deviceId);
      await _setMeta(db, 'g_pushed', '0');
      await _setMeta(db, 'g_dump', '1');
    } else if (sender.isAdmin) {
      // An admin lost history: every device re-sends what it authored.
      await _setMeta(db, 'g_pushed', '0');
    }
  }

  Future<void> _onBye(Database db, GroupMember sender, MemberDoc doc) async {
    if (!sender.isActive) return;
    final me = (await identity()).deviceId;
    final admins = doc.admins.map((m) => m.deviceId).where((d) => d != sender.deviceId).toList()
      ..sort();
    // One admin handles it, so the key rotates once.
    if (admins.isEmpty || admins.first != me) return;
    try {
      await removeMember(sender.deviceId);
    } catch (_) {}
  }

  Future<void> _fetchJoins(Database db, GroupAuth auth) async {
    final reqs = await _gt.joinRequests(auth);
    final me = await identity();
    final ids = <String>{};
    for (final r in reqs) {
      ids.add(r.deviceId);
      final have = await db.query('sync_joins',
          where: 'device_id = ?', whereArgs: [r.deviceId]);
      if (have.isNotEmpty) continue;
      try {
        final x = unb64(r.publicKey);
        if (x.length != 32) continue;
        final key = await _directKey(auth.groupId, r.deviceId, x);
        final clear = await openBytes(r.blob,
            key: key, aad: '${auth.groupId}|join|${r.deviceId}');
        final j = jsonDecode(utf8.decode(clear));
        if (j is! Map || j['d'] != r.deviceId || j['g'] != auth.groupId) continue;
        final s = unb64(j['s'] as String);
        if (s.length != 32 || r.deviceId == me.deviceId) continue;
        final legacy = await db.query('sync_peers',
            columns: ['name'], where: 'peer_id = ?', whereArgs: [r.deviceId]);
        await db.insert('sync_joins', {
          'device_id': r.deviceId,
          'public_key': r.publicKey,
          'sign_key': b64(s),
          'legacy_name': legacy.isEmpty ? null : legacy.first['name'],
          'created_at': _now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {
        // Sealed to another admin of this group: that admin approves it.
      }
    }
    final local = await db.query('sync_joins', columns: ['device_id']);
    for (final r in local) {
      if (!ids.contains(r['device_id'])) {
        await db.delete('sync_joins', where: 'device_id = ?', whereArgs: [r['device_id']]);
      }
    }
  }

  Future<int> _groupPush(Database db, GroupAuth auth) async {
    final doc = await _doc(db);
    if (doc == null) return 0;
    final key = (await _keys(db))[doc.epoch];
    if (key == null) return 0;
    final me = await identity();
    final admin = doc.member(me.deviceId)?.isAdmin ?? false;
    final dump = admin && await _meta(db, 'g_dump') == '1';
    // Own edits always; admins also forward edits from old-style pairs;
    // a dump (newcomer / resync) sends everything.
    final where = dump
        ? 'lseq > ?'
        : (admin ? "lseq > ? AND src NOT LIKE 'g:%'" : "lseq > ? AND src = ''");
    var cursor = await _metaInt(db, 'g_pushed');
    var pushed = 0;
    for (var round = 0; round < 20; round++) {
      final rows = await db.query('sync_records',
          where: where, whereArgs: [cursor], orderBy: 'lseq', limit: 400);
      if (rows.isEmpty) {
        if (dump) await _delMeta(db, 'g_dump');
        break;
      }
      final items = <GroupItem>[];
      var bytes = 0;
      var batch = <Map<String, Object?>>[];
      var batchBytes = 0;
      var last = cursor;

      Future<void> flush() async {
        if (batch.isEmpty) return;
        final it = await _seal({'m': 'chg', 'c': batch},
            gid: auth.groupId, epoch: doc.epoch, key: key, recipients: doc.members);
        items.add(it);
        bytes += it.blob.ct.length;
        pushed += batch.length;
        batch = [];
        batchBytes = 0;
      }

      for (final r in rows) {
        final kind = r['kind']! as String;
        final rid = r['rid']! as String;
        final deleted = r['deleted'] == 1;
        final data = deleted ? null : await _payloadFor(db, kind, rid);
        last = r['lseq']! as int;
        if (!deleted && data == null) continue;
        final change = SyncChange(
          kind: kind,
          rid: rid,
          ts: r['ts']! as int,
          origin: r['origin']! as String,
          deleted: deleted,
          data: data,
        ).toJson();
        final size = jsonEncode(change).length;
        if (batch.isNotEmpty && batchBytes + size > SyncEngine._msgLimit) await flush();
        batch.add(change);
        batchBytes += size;
        if (kind == 'photo') await flush();
        if (bytes >= SyncEngine._requestLimit) {
          await flush();
          break;
        }
      }
      await flush();
      if (items.isNotEmpty) await _gt.pushGroup(auth, items);
      cursor = last;
      await _setMeta(db, 'g_pushed', '$cursor');
      if (rows.length < 400 && bytes < SyncEngine._requestLimit) {
        if (dump) await _delMeta(db, 'g_dump');
        break;
      }
    }
    return pushed;
  }

  /// One group round: pull (admins also fetch join requests), then the
  /// caller scans, then [_groupPushPhase].
  Future<int> _groupPullPhase(Database db) async {
    final auth = await _auth(db);
    if (auth == null) return 0;
    var applied = 0;
    if (await _gState(db) == GroupState.active) applied += await _applyDeferred(db);
    applied += await _groupPull(db, auth);
    if (await _gState(db) != GroupState.active) return applied;
    final doc = await _doc(db);
    if (doc?.member(auth.deviceId)?.isAdmin ?? false) await _fetchJoins(db, auth);
    await _flushOutbox(db, auth);
    // Legacy pairs of devices that are group members now: retire them.
    if (doc != null) {
      for (final p in await db.query('sync_peers')) {
        if (doc.member(p['peer_id']! as String)?.isActive ?? false) {
          await _dropLegacy(db, p['peer_id']! as String);
        }
      }
    }
    await db.delete('sync_trash', where: 'deleted_at < ?', whereArgs: [_now - _kTrashKeepMs]);
    return applied;
  }

  Future<int> _groupPushPhase(Database db) async {
    if (await _gState(db) != GroupState.active) return 0;
    final auth = await _auth(db);
    if (auth == null) return 0;
    final n = await _groupPush(db, auth);
    await _flushOutbox(db, auth);
    await _setMeta(db, 'g_last_ok', '${_clock().millisecondsSinceEpoch}');
    return n;
  }

  // ------------------------------------------------------------ test hooks

  /// Tests only: offer a member list as if it arrived from the relay.
  Future<bool> applyForeignDocForTest(MemberDoc d) async =>
      _acceptDocs(await _db(), [d]);

  /// Tests only: changes as if group member [senderId] sent them.
  Future<int> applyGroupChangesForTest(
    String senderId,
    List<SyncChange> changes,
  ) async {
    final db = await _db();
    final doc = (await _doc(db))!;
    return _onChanges(db, doc.member(senderId)!, doc, {
      'c': [for (final c in changes) c.toJson()],
    });
  }
}
