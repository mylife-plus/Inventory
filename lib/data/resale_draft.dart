import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A receipt that was undone via Items Sold → receipt → Edit → Continue.
///
/// The sale is already removed (stock restored); its items sit in the Sell
/// cart. Completing the sale again re-creates it under the same receipt
/// number and date. Persisted so nothing is lost if the app is closed or
/// killed before the sale is completed again.
@immutable
class ResaleDraft {
  const ResaleDraft({
    required this.saleId,
    required this.createdAt,
    required this.lines,
    List<SaleLine>? originalLines,
    this.customerId,
    this.customerName,
  }) : originalLines = originalLines ?? lines;

  /// Original sale id (= receipt number) to re-use.
  final String saleId;

  /// Original sale date to re-use.
  final DateTime createdAt;

  /// `null` = Guest.
  final String? customerId;
  final String? customerName;

  /// Current cart (kept in sync while editing).
  final List<SaleLine> lines;

  /// The receipt's lines exactly as sold — Cancel puts these back.
  final List<SaleLine> originalLines;

  String get receiptNumber =>
      (saleId.length > 8 ? saleId.substring(0, 8) : saleId).toUpperCase();

  factory ResaleDraft.fromSale(Sale sale) => ResaleDraft(
    saleId: sale.id,
    createdAt: sale.createdAt,
    customerId: sale.customerId,
    customerName: sale.customerName,
    lines: List<SaleLine>.from(sale.lines),
    originalLines: List<SaleLine>.from(sale.lines),
  );

  /// The receipt as it was before Edit (for Cancel).
  Sale get originalSale => Sale(
    id: saleId,
    customerId: customerId,
    customerName: customerName,
    total: originalLines.fold<double>(0, (s, l) => s + l.lineTotal),
    createdAt: createdAt,
    lines: originalLines,
  );

  ResaleDraft copyWith({List<SaleLine>? lines}) => ResaleDraft(
    saleId: saleId,
    createdAt: createdAt,
    customerId: customerId,
    customerName: customerName,
    lines: lines ?? this.lines,
    originalLines: originalLines,
  );

  Map<String, Object?> toJson() => {
    'saleId': saleId,
    'createdAt': createdAt.toIso8601String(),
    'customerId': customerId,
    'customerName': customerName,
    'lines': [for (final l in lines) _lineJson(l)],
    'originalLines': [for (final l in originalLines) _lineJson(l)],
  };

  static Map<String, Object?> _lineJson(SaleLine l) => {
    'itemId': l.itemId,
    'title': l.title,
    'unitPrice': l.unitPrice,
    'quantity': l.quantity,
    'unit': l.unit,
    'photoPath': l.photoPath,
  };

  static List<SaleLine> _parseLines(Object? raw) => [
    for (final e in (raw as List? ?? const []))
      SaleLine(
        itemId: e['itemId'] as String,
        title: e['title'] as String,
        unitPrice: (e['unitPrice'] as num).toDouble(),
        quantity: (e['quantity'] as num).toDouble(),
        unit: e['unit'] as String?,
        photoPath: e['photoPath'] as String?,
      ),
  ];

  static ResaleDraft? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final lines = _parseLines(m['lines']);
      final original = m.containsKey('originalLines')
          ? _parseLines(m['originalLines'])
          : null;
      return ResaleDraft(
        saleId: m['saleId'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        customerId: m['customerId'] as String?,
        customerName: m['customerName'] as String?,
        lines: lines,
        originalLines: original,
      );
    } catch (e) {
      debugPrint('Bad resale draft: $e');
      return null;
    }
  }
}

final resaleDraftProvider =
    StateNotifierProvider<ResaleDraftNotifier, ResaleDraft?>(
      (ref) => ResaleDraftNotifier(),
    );

class ResaleDraftNotifier extends StateNotifier<ResaleDraft?> {
  ResaleDraftNotifier() : super(null) {
    _loaded = _load();
  }

  static const prefKey = 'pending_resale_v1';

  late final Future<void> _loaded;

  /// True when the current draft was left over from a previous app run
  /// (the app was closed / killed in the middle of an edit).
  bool loadedFromDisk = false;

  /// Completes once a draft saved before the app was closed is loaded.
  Future<void> get loaded => _loaded;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = ResaleDraft.tryParse(prefs.getString(prefKey));
      // Don't overwrite a draft started meanwhile.
      if (mounted && state == null && draft != null) {
        state = draft;
        loadedFromDisk = true;
      }
    } catch (e) {
      debugPrint('Loading resale draft failed: $e');
    }
  }

  Future<void> start(ResaleDraft draft) async {
    state = draft;
    await _save();
  }

  /// Keep the saved copy in step with the cart (survives an app kill).
  void updateLines(List<SaleLine> lines) {
    final d = state;
    if (d == null || listEquals(d.lines, lines)) return;
    state = d.copyWith(lines: List<SaleLine>.from(lines));
    unawaited(_save());
  }

  Future<void> clear() async {
    state = null;
    loadedFromDisk = false;
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final d = state;
      if (d == null) {
        await prefs.remove(prefKey);
      } else {
        await prefs.setString(prefKey, jsonEncode(d.toJson()));
      }
    } catch (e) {
      debugPrint('Saving resale draft failed: $e');
    }
  }
}
