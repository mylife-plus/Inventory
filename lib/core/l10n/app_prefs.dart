import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPrefs {
  const AppPrefs({
    this.localeCode = 'en',
    this.darkMode = true,
    this.pinLock = false,
    this.prefsSetupDone = false,
  });

  final String localeCode;
  final bool darkMode;
  final bool pinLock;
  /// First-launch language + currency picked.
  final bool prefsSetupDone;

  AppPrefs copyWith({
    String? localeCode,
    bool? darkMode,
    bool? pinLock,
    bool? prefsSetupDone,
  }) {
    return AppPrefs(
      localeCode: localeCode ?? this.localeCode,
      darkMode: darkMode ?? this.darkMode,
      pinLock: pinLock ?? this.pinLock,
      prefsSetupDone: prefsSetupDone ?? this.prefsSetupDone,
    );
  }

  Locale get locale => Locale(localeCode);
}

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final appPrefsProvider =
    AsyncNotifierProvider<AppPrefsNotifier, AppPrefs>(AppPrefsNotifier.new);

/// Live translator — rebuilds whenever locale changes.
final tProvider = Provider<S>((ref) {
  final code = ref.watch(appPrefsProvider).valueOrNull?.localeCode ?? 'en';
  return S(code);
});

class AppPrefsNotifier extends AsyncNotifier<AppPrefs> {
  static const _kLocale = 'locale';
  static const _kDark = 'dark_mode';
  static const _kPin = 'pin_lock';
  static const _kPrefsSetup = 'prefs_setup_done';

  @override
  Future<AppPrefs> build() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocale) ?? 'en';
    return AppPrefs(
      localeCode: S.supported.containsKey(code) ? code : 'en',
      darkMode: prefs.getBool(_kDark) ?? true,
      pinLock: prefs.getBool(_kPin) ?? false,
      prefsSetupDone: prefs.getBool(_kPrefsSetup) ?? false,
    );
  }

  Future<void> setLocale(String code) async {
    if (!S.supported.containsKey(code)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, code);
    final current = state.value ?? const AppPrefs();
    state = AsyncData(current.copyWith(localeCode: code));
  }

  Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDark, value);
    state =
        AsyncData((state.value ?? const AppPrefs()).copyWith(darkMode: value));
  }

  Future<void> setPinLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPin, value);
    state =
        AsyncData((state.value ?? const AppPrefs()).copyWith(pinLock: value));
  }

  Future<void> markPrefsSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsSetup, true);
    state = AsyncData(
      (state.value ?? const AppPrefs()).copyWith(prefsSetupDone: true),
    );
  }
}
