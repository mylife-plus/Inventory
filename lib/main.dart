import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/app.dart';
import 'package:inventory_app/core/print/print_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const ProviderScope(child: InventoryApp()));
}
