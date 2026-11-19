import 'dart:async';
import 'package:community_package/community_package.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/web/safe_web_focus_binding.dart';
import 'package:inventory_app/core/web/web_sqlite.dart';
import 'package:inventory_app/data/reset/app_reset.dart';

/// Backend of the community feedback screens (Settings → Community App).
const _communityBackendUrl = 'https://api.mylife.plus';

/// A screen title from [S] in the app's current language.
String Function(BuildContext) _title(String key) =>
    (context) => S(Localizations.localeOf(context).languageCode)(key);

/// Screens for the Problem form's screen picker, in the order a user reaches
/// them (lib/core/routing/app_router.dart). English names, saved with each
/// Problem; labels shown in the app's language.
final _communityScreens = [
  ScreenNode(
    'Inventory',
    label: _title('inventory'),
    children: [
      ScreenNode('New Item', label: _title('new_item')),
      ScreenNode(
        'Edit Item',
        label: _title('edit_item'),
        children: [
          ScreenNode(
            'QR Label',
            label: _title('qr_label'),
            children: [
              ScreenNode('Print Preview', label: _title('print_preview_title')),
            ],
          ),
        ],
      ),
      ScreenNode(
        'Sell Items',
        label: _title('sell_items'),
        children: [
          ScreenNode('Add Items', label: _title('add_items')),
          ScreenNode('QR Scanner', label: _title('qr_scanner')),
          ScreenNode(
            'Select Customer',
            label: _title('select_customer'),
            children: [
              ScreenNode('New Customer', label: _title('new_customer')),
            ],
          ),
          ScreenNode('Receipt', label: _title('receipt')),
        ],
      ),
    ],
  ),
  ScreenNode(
    'Customers',
    label: _title('customers'),
    children: [
      ScreenNode('New Customer', label: _title('new_customer')),
      ScreenNode(
        'Customer Details',
        label: _title('screen_customer_details'),
        children: [
          ScreenNode('Edit Customer', label: _title('edit_customer')),
          ScreenNode('Receipt', label: _title('receipt')),
        ],
      ),
    ],
  ),
  ScreenNode(
    'Turnover',
    label: _title('turnover'),
    children: [ScreenNode('Edit Item', label: _title('edit_item'))],
  ),
  ScreenNode(
    'Settings',
    label: _title('settings'),
    children: [
      ScreenNode('Receipt Details', label: _title('receipt_details')),
      ScreenNode(
        'Receipts',
        label: _title('receipts'),
        children: [
          ScreenNode(
            'Receipts of a Year',
            label: _title('screen_receipts_of_year'),
            children: [ScreenNode('Receipt', label: _title('receipt'))],
          ),
        ],
      ),
    ],
  ),
  ScreenNode('Setup', label: _title('screen_setup')),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: suppress known debug assert when view-focus runs before Overlay layout.
  installWebFocusAssertFilter();
  // Web: sqflite via wasm/IndexedDB (path_provider docs dir does not exist).
  initWebSqlite();

  // No network work here; the feedback screens load their data when opened.
  await CommunityPackage.init(
    CommunityConfig(
      backendUrl: _communityBackendUrl,
      appId: 'inventory',
      privacyPolicyUrl: 'https://www.mylife.plus/inventory#h.vth7hdenrad4',
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
