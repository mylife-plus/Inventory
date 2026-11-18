import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/web/safe_web_focus_binding.dart';
import 'package:inventory_app/core/web/web_sqlite.dart';
import 'package:inventory_app/data/reset/app_reset.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: suppress known debug assert when view-focus runs before Overlay layout.
  installWebFocusAssertFilter();
  // Web: sqflite via wasm/IndexedDB (path_provider docs dir does not exist).
  initWebSqlite();

  // Inter is bundled in assets/google_fonts/ (same files google_fonts would
  // download), so the app never fetches fonts over the network.
  GoogleFonts.config.allowRuntimeFetching = false;
  // Print fonts are not needed for the first frame: warm them a few
  // seconds after launch, when the app is idle.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Timer(const Duration(seconds: 4), () => unawaited(PrintService.preload()));
  });
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['google_fonts'], license);
  });

  // Phone app — lock portrait on Android + iOS (same UX everywhere).
  // (Not awaited: the manifest already locks portrait on Android, so the
  // first frame doesn't wait for this platform call.)
  unawaited(
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]),
  );

  // Consistent status / nav bars with the dark inventory chrome.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  runApp(const AppRoot());
}
