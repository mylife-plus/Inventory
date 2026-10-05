import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/data/repositories/repositories.dart';

/// Opens receipt-details once when shop header is incomplete.
/// Returns `true` when details are ready (already saved or just saved).
Future<bool> ensureShopReceiptDetails(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(shopSettingsProvider).valueOrNull;
  if (settings == null) return false;
  if (settings.hasReceiptDetails) return true;

  final saved = await context.push<bool>('/settings/receipt');
  if (!context.mounted) return false;

  final again = ref.read(shopSettingsProvider).valueOrNull;
  return saved == true || (again?.hasReceiptDetails ?? false);
}
