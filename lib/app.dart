import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/notifications/in_app_notifications.dart';
import 'package:inventory_app/core/routing/app_router.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/resale_draft.dart';
import 'package:inventory_app/features/sell/presentation/sell_page.dart';
import 'package:inventory_app/features/lock/pin_gate.dart';

class InventoryApp extends ConsumerWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final prefs = ref.watch(appPrefsProvider).valueOrNull ?? const AppPrefs();

    // Receipt Edit → Continue (undone sale being re-done): a draft saved
    // before the app was closed refills the empty cart + customer, and cart
    // changes are saved so they survive leaving / killing the app.
    ref.listen<ResaleDraft?>(resaleDraftProvider, (prev, next) {
      if (prev == null && next != null && ref.read(cartProvider).isEmpty) {
        restoreResaleIntoCart(
          ref.read,
          next,
          guestName: S(prefs.localeCode)('guest'),
        );
      }
    });
    ref.listen(cartProvider, (_, next) {
      if (next.isNotEmpty) {
        ref.read(resaleDraftProvider.notifier).updateLines(next);
      }
    });

    return MaterialApp.router(
      title: S(prefs.localeCode)('app_name'),
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: prefs.darkMode ? ThemeMode.dark : ThemeMode.light,
      locale: prefs.locale,
      supportedLocales: S.supported.keys.map(Locale.new).toList(),
      localeResolutionCallback: (device, supported) {
        return prefs.locale;
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Keep layout stable on Android when system font size is huge.
        final scale = mq.textScaler.scale(1).clamp(0.90, 1.12);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: PinGate(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
