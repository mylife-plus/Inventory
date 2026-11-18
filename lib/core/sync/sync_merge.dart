import 'dart:convert';

import 'package:inventory_app/core/sync/sync_crypto.dart';

/// Synced record kinds, in apply order (parents before children).
const kSyncKinds = ['shop', 'cat', 'cust', 'item', 'sale', 'photo'];

int syncKindRank(String kind) {
  final i = kSyncKinds.indexOf(kind);
  return i < 0 ? kSyncKinds.length : i;
}

/// Last-write-wins: the newer edit time wins; an exact tie goes to the
/// larger author device id so both devices pick the same winner.
bool remoteWins({
  required int localTs,
  required String localOrigin,
  required int remoteTs,
  required String remoteOrigin,
}) {
  if (remoteTs != localTs) return remoteTs > localTs;
  return remoteOrigin.compareTo(localOrigin) > 0;
}

/// Next edit time for a locally changed record: wall clock, but always after
/// the version it replaces (guards against a peer clock running ahead).
int nextEditTs(int nowMs, int previousTs) =>
    nowMs > previousTs ? nowMs : previousTs + 1;

Object? _canon(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(v[k])};
  }
  if (v is List) return v.map(_canon).toList();
  return v;
}

/// Stable JSON (sorted keys) for hashing and transport.
String canonicalJson(Object? v) => jsonEncode(_canon(v));

/// Content hash used to detect local edits between scans.
String recordHash(Object? data) => sha256Hex(utf8.encode(canonicalJson(data)));
