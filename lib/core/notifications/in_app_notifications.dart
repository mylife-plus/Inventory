import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

/// App-wide messenger so banners work from any route / after navigation.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Fire stock-below-threshold notices as top MaterialBanners (in-app).
void notifyLowStockItems(WidgetRef ref, List<InventoryItem> items) {
  if (items.isEmpty) return;
  final t = ref.read(tProvider);
  AppHaptics.heavy();

  void show() {
    final messenger = rootScaffoldMessengerKey.currentState;
    final ctx = rootScaffoldMessengerKey.currentContext;
    if (messenger == null || ctx == null) return;

    final p = AppPalette.of(ctx);
    final String body;
    if (items.length == 1) {
      final item = items.first;
      body = t.tr('low_stock_item_body', {
        'title': item.title,
        'qty': formatQty(item.amount),
        'level': formatQty(item.alertAmount),
      });
    } else {
      body = t.tr('low_stock_multi_body', {
        'count': '${items.length}',
        'titles': items.map((e) => e.title).join(', '),
      });
    }

    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          elevation: 6,
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          backgroundColor: p.cardElevated,
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.fabBorder.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: p.fabBorder,
              size: 22,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('low_stock'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  height: 1.3,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: Text(
                t('done'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: p.fabBorder,
                ),
              ),
            ),
          ],
        ),
      );

    Future<void>.delayed(const Duration(seconds: 7), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  // After navigation / frame so messenger + theme are ready.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) => show());
  });
}
