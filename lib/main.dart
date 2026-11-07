import 'dart:async';
import 'package:community_package/community_package.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/web/safe_web_focus_binding.dart';
import 'package:inventory_app/core/web/web_sqlite.dart';
import 'package:inventory_app/data/reset/app_reset.dart';

/// Backend of the community feedback screens (Settings → Community App).
const _communityBackendUrl = 'https://community-dev.qureshicreatives.workers.dev';

/// Screens for the Problem form's screen picker, in the order a user reaches
/// them (lib/core/routing/app_router.dart). English names, saved with each
/// Problem.
const _communityScreens = [
  ScreenNode(
    'Inventory',
    children: [
      ScreenNode('New Item'),
      ScreenNode(
        'Edit Item',
        children: [
          ScreenNode('QR Label', children: [ScreenNode('Print Preview')]),
        ],
      ),
      ScreenNode(
        'Sell Items',
        children: [
          ScreenNode('Add Items'),
          ScreenNode('QR Scanner'),
          ScreenNode('Select Customer', children: [ScreenNode('New Customer')]),
          ScreenNode('Receipt'),
        ],
      ),
    ],
  ),
  ScreenNode(
    'Customers',
    children: [
      ScreenNode('New Customer'),
      ScreenNode(
        'Customer Details',
        children: [ScreenNode('Edit Customer'), ScreenNode('Receipt')],
      ),
    ],
  ),
  ScreenNode('Turnover', children: [ScreenNode('Edit Item')]),
  ScreenNode(
    'Settings',
    children: [
      ScreenNode('Receipt Details'),
      ScreenNode(
        'Receipts',
        children: [
          ScreenNode('Receipts of a Year', children: [ScreenNode('Receipt')]),
        ],
      ),
    ],
  ),
  ScreenNode('Setup'),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: suppress known debug assert when view-focus runs before Overlay layout.
  installWebFocusAssertFilter();
  // Web: sqflite via wasm/IndexedDB (path_provider docs dir does not exist).
  initWebSqlite();

  // No network work here; the feedback screens load their data when opened.
  await CommunityPackage.init(
    const CommunityConfig(
      backendUrl: _communityBackendUrl,
      appId: 'inventory',
      screens: _communityScreens,
    ),
  );

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
