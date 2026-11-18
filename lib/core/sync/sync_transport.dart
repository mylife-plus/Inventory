import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:inventory_app/core/sync/sync_crypto.dart';

class SyncOfflineException implements Exception {
  const SyncOfflineException([this.message = 'offline']);
  final String message;
  @override
  String toString() => 'SyncOfflineException: $message';
}

class SyncServerException implements Exception {
  const SyncServerException(this.status, [this.message = '']);
  final int status;
  final String message;
  @override
  String toString() => 'SyncServerException($status): $message';
}

class PulledBlob {
  const PulledBlob(this.seq, this.blob);
  final int seq;
  final SealedBlob blob;
}

class PullPage {
  const PullPage(this.items, {this.more = false});
  final List<PulledBlob> items;
  final bool more;
}

/// Device credentials for the v2 group mailbox.
class GroupAuth {
  const GroupAuth({
    required this.groupId,
    required this.deviceId,
    required this.token,
  });
  final String groupId;
  final String deviceId;
  final String token;
}

/// One sealed item in the group mailbox. [to] is set for messages meant
/// for a single device (sealed with a direct key, [epoch] 0).
class GroupItem {
  const GroupItem({
    required this.blob,
    required this.epoch,
    this.to,
    this.seq = 0,
    this.sender = '',
  });
  final SealedBlob blob;
  final int epoch;
  final String? to;
  final int seq;
  final String sender;
}

class GroupPullPage {
  const GroupPullPage({
    required this.items,
    required this.status,
    required this.serverNow,
    this.role = 'member',
    this.more = false,
    this.gap = false,
  });
  final List<GroupItem> items;

  /// `pending` (waiting for Approve) or `active`.
  final String status;
  final String role;
  final int serverNow;
  final bool more;

  /// Ciphertext this device never fetched was already purged.
  final bool gap;
}

class GroupJoinRequest {
  const GroupJoinRequest({
    required this.deviceId,
    required this.publicKey,
    required this.blob,
  });
  final String deviceId;
  final String publicKey;
  final SealedBlob blob;
}

/// v2 relay: one mailbox per shop group. Server-side it enforces device
/// tokens, admin-only management and revocation; content stays sealed.
abstract class GroupTransport {
  Future<void> createGroup(GroupAuth auth, {required String publicKey});
  Future<void> addInvite(
    GroupAuth auth, {
    required String secretHash,
    required int expiresAt,
  });
  Future<void> join(
    GroupAuth auth, {
    required String secret,
    required String publicKey,
    required SealedBlob request,
  });
  Future<List<GroupJoinRequest>> joinRequests(GroupAuth auth);
  Future<int> approve(GroupAuth auth, String deviceId, {required String role});
  Future<void> reject(GroupAuth auth, String deviceId);

  /// Returns the mailbox position at revocation.
  Future<int> revoke(GroupAuth auth, String deviceId);
  Future<void> setRole(GroupAuth auth, String deviceId, String role);
  Future<void> leave(GroupAuth auth);
  Future<List<int>> pushGroup(GroupAuth auth, List<GroupItem> items);
  Future<GroupPullPage> pullGroup(GroupAuth auth, {required int after});
}

/// Relay mailbox per pair. Only ciphertext crosses this boundary.
abstract class SyncTransport {
  Future<List<int>> push({
    required String pairId,
    required String auth,
    required String sender,
    required List<SealedBlob> blobs,
  });

  Future<PullPage> pull({
    required String pairId,
    required String auth,
    required String device,
    required int after,
  });

  Future<void> drop({required String pairId, required String auth});
}

class HttpSyncTransport implements SyncTransport, GroupTransport {
  HttpSyncTransport(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Map<String, String> _h(String auth) => {
        'authorization': 'Bearer $auth',
        'content-type': 'application/json',
      };

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() call, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw const SyncOfflineException('timeout');
    } on SocketException catch (e) {
      throw SyncOfflineException(e.message);
    } on http.ClientException catch (e) {
      throw SyncOfflineException(e.message);
    } on HandshakeException catch (e) {
      throw SyncOfflineException(e.message);
    }
    Object? body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {}
    if (res.statusCode != 200 || body is! Map<String, dynamic>) {
      throw SyncServerException(
        res.statusCode,
        body is Map ? '${body['error']}' : 'bad response',
      );
    }
    return body;
  }

  @override
  Future<List<int>> push({
    required String pairId,
    required String auth,
    required String sender,
    required List<SealedBlob> blobs,
  }) async {
    final payload = jsonEncode({
      'sender': sender,
      'items': [
        for (final b in blobs) {'iv': b.iv, 'ct': b.ct},
      ],
    });
    final size = payload.length;
    final body = await _send(
      () => _client.post(
        _u('/v1/pairs/$pairId/changes'),
        headers: _h(auth),
        body: payload,
      ),
      timeout: Duration(seconds: 20 + size ~/ 100000),
    );
    return [for (final s in (body['seqs'] as List? ?? const [])) (s as num).toInt()];
  }

  @override
  Future<PullPage> pull({
    required String pairId,
    required String auth,
    required String device,
    required int after,
  }) async {
    final body = await _send(
      () => _client.get(
        _u('/v1/pairs/$pairId/changes', {
          'device': device,
          'after': '$after',
        }),
        headers: _h(auth),
      ),
      timeout: const Duration(seconds: 60),
    );
    final items = <PulledBlob>[];
    for (final it in (body['items'] as List? ?? const [])) {
      if (it is! Map) continue;
      items.add(PulledBlob(
        (it['seq'] as num).toInt(),
        SealedBlob(iv: '${it['iv']}', ct: '${it['ct']}'),
      ));
    }
    return PullPage(items, more: body['more'] == true);
  }

  @override
  Future<void> drop({required String pairId, required String auth}) async {
    await _send(
      () => _client.delete(_u('/v1/pairs/$pairId'), headers: _h(auth)),
      timeout: const Duration(seconds: 8),
    );
  }

  // ------------------------------------------------------------ v2 groups

  Map<String, String> _gh(GroupAuth a) => {
        'authorization': 'Bearer ${a.token}',
        'x-device': a.deviceId,
        'content-type': 'application/json',
      };

  String _g(GroupAuth a, [String rest = '']) => '/v2/groups/${a.groupId}$rest';

  Future<Map<String, dynamic>> _post(
    GroupAuth a,
    String rest,
    Object? body, {
    Duration timeout = const Duration(seconds: 20),
  }) =>
      _send(
        () => _client.post(
          _u(_g(a, rest)),
          headers: _gh(a),
          body: jsonEncode(body ?? const {}),
        ),
        timeout: timeout,
      );

  @override
  Future<void> createGroup(GroupAuth auth, {required String publicKey}) =>
      _post(auth, '', {'x_pub': publicKey});

  @override
  Future<void> addInvite(
    GroupAuth auth, {
    required String secretHash,
    required int expiresAt,
  }) =>
      _post(auth, '/invites', {
        'secret_hash': secretHash,
        'expires_at': expiresAt,
      });

  @override
  Future<void> join(
    GroupAuth auth, {
    required String secret,
    required String publicKey,
    required SealedBlob request,
  }) =>
      _post(auth, '/join', {
        'secret': secret,
        'device': auth.deviceId,
        'x_pub': publicKey,
        'iv': request.iv,
        'ct': request.ct,
      });

  @override
  Future<List<GroupJoinRequest>> joinRequests(GroupAuth auth) async {
    final body = await _send(
      () => _client.get(_u(_g(auth, '/joins')), headers: _gh(auth)),
    );
    return [
      for (final it in (body['items'] as List? ?? const []))
        if (it is Map)
          GroupJoinRequest(
            deviceId: '${it['device']}',
            publicKey: '${it['x_pub']}',
            blob: SealedBlob(iv: '${it['iv']}', ct: '${it['ct']}'),
          ),
    ];
  }

  @override
  Future<int> approve(
    GroupAuth auth,
    String deviceId, {
    required String role,
  }) async {
    final b = await _post(auth, '/devices/$deviceId/approve', {'role': role});
    return (b['start_seq'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> reject(GroupAuth auth, String deviceId) =>
      _post(auth, '/devices/$deviceId/reject', null);

  @override
  Future<int> revoke(GroupAuth auth, String deviceId) async {
    final b = await _post(auth, '/devices/$deviceId/revoke', null);
    return (b['seq'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> setRole(GroupAuth auth, String deviceId, String role) =>
      _post(auth, '/devices/$deviceId/role', {'role': role});

  @override
  Future<void> leave(GroupAuth auth) => _post(
        auth,
        '/leave',
        null,
        timeout: const Duration(seconds: 8),
      );

  @override
  Future<List<int>> pushGroup(GroupAuth auth, List<GroupItem> items) async {
    final payload = {
      'items': [
        for (final it in items)
          {
            'iv': it.blob.iv,
            'ct': it.blob.ct,
            'epoch': it.epoch,
            if (it.to != null) 'to': it.to,
          },
      ],
    };
    final size = items.fold<int>(0, (n, it) => n + it.blob.ct.length);
    final body = await _post(
      auth,
      '/changes',
      payload,
      timeout: Duration(seconds: 20 + size ~/ 100000),
    );
    return [
      for (final s in (body['seqs'] as List? ?? const [])) (s as num).toInt(),
    ];
  }

  @override
  Future<GroupPullPage> pullGroup(GroupAuth auth, {required int after}) async {
    final body = await _send(
      () => _client.get(
        _u(_g(auth, '/changes'), {'after': '$after'}),
        headers: _gh(auth),
      ),
      timeout: const Duration(seconds: 60),
    );
    return GroupPullPage(
      items: [
        for (final it in (body['items'] as List? ?? const []))
          if (it is Map)
            GroupItem(
              seq: (it['seq'] as num).toInt(),
              sender: '${it['sender']}',
              to: it['to'] as String?,
              epoch: (it['epoch'] as num?)?.toInt() ?? 0,
              blob: SealedBlob(iv: '${it['iv']}', ct: '${it['ct']}'),
            ),
      ],
      status: '${body['status'] ?? 'active'}',
      role: '${body['role'] ?? 'member'}',
      serverNow: (body['now'] as num?)?.toInt() ?? 0,
      more: body['more'] == true,
      gap: body['gap'] == true,
    );
  }
}
