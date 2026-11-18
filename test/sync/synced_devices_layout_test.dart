import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/sync/sync_controller.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_group.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/features/settings/presentation/synced_devices_page.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';

/// Nov 13 client test on two phones: no QR ever showed (the admin-group
/// server is not deployed yet) and button labels wrapped onto two lines.
/// Renders the Synced Devices screens at a small phone width in all five
/// languages: every button label stays on one line, nothing overflows,
/// and a device can always get to a QR code.
///
/// Screenshots: `SYNC_SHOTS_DIR=/some/dir flutter test <this file>`.
const _me = 'a1b2c3d4e5f60718';
const _other = '9f8e7d6c5b4a3921';
const _newcomer = '5566778899aabbcc';

class _FakePrefs extends AppPrefsNotifier {
  _FakePrefs(this.code);
  final String code;
  @override
  Future<AppPrefs> build() async => AppPrefs(localeCode: code);
}

class _FakeSync extends SyncController {
  _FakeSync(this.initial, {this.serverDeployed = false});
  final SyncState initial;
  final bool serverDeployed;
  int pairingCodeCalls = 0;

  @override
  SyncState build() => initial;
  @override
  Future<String> myDeviceId() async => _me;
  @override
  Future<void> syncNow() async {}
  @override
  Future<void> reloadPeers() async {}
  @override
  Future<String> pairingCode() async {
    pairingCodeCalls++;
    return 'inventory-sync-pair-fake-$_me';
  }

  @override
  Future<void> createGroup() async {
    if (!serverDeployed) throw const GroupError('server_update');
    state = state.copyWith(group: _adminGroup(joins: false));
  }

  int dissolveCalls = 0;
  int leaveCalls = 0;
  @override
  Future<void> dissolveGroup() async {
    dissolveCalls++;
    state = state.copyWith(group: const GroupInfo(state: GroupState.none));
  }

  @override
  Future<void> leaveGroup() async {
    leaveCalls++;
    state = state.copyWith(group: const GroupInfo(state: GroupState.none));
  }

  @override
  Future<String> createInvite() async => 'inventory-sync-invite-fake';
  @override
  Future<List<SyncTrashEntry>> trash() async => [
        SyncTrashEntry(
          id: 1,
          kind: 'item',
          rid: 'r1',
          title: 'Kaffeebohnen Espresso 1kg',
          byDevice: _other,
          deletedAt: DateTime(2026, 11, 13, 14, 5),
        ),
        SyncTrashEntry(
          id: 2,
          kind: 'cust',
          rid: 'r2',
          title: 'Johannes',
          byDevice: _other,
          deletedAt: DateTime(2026, 11, 12, 9, 30),
        ),
      ];
}

GroupMember _m(String id, String name, String role) => GroupMember(
      deviceId: id,
      name: name,
      role: role,
      status: 'active',
      publicKey: Uint8List(32),
      signKey: Uint8List(32),
      addedAt: 0,
    );

GroupInfo _adminGroup({bool joins = true}) => GroupInfo(
      state: GroupState.active,
      groupId: 'g',
      myId: _me,
      doc: MemberDoc(
        groupId: 'g',
        version: 2,
        epoch: 1,
        issuedAt: 0,
        signer: _me,
        members: joins
            ? [_m(_me, '', 'admin'), _m(_other, 'Counter phone', 'member')]
            : [_m(_me, '', 'admin')],
      ),
      joins: joins
          ? [GroupJoinCandidate(deviceId: _newcomer, createdAt: DateTime(2026))]
          : const [],
      trashCount: 2,
      lastSyncAt: DateTime(2026, 11, 13, 18, 30),
    );

final _shotsDir = Platform.environment['SYNC_SHOTS_DIR'];
final _boundary = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotsDir == null) return;
  await tester.runAsync(() async {
    final ro = _boundary.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final ui.Image img = await ro.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('$_shotsDir/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// Every label inside a button is one line high and nothing overflowed.
void _expectButtonsOneLine(WidgetTester tester, String where) {
  final ex = tester.takeException();
  if (ex != null) {
    void walk(RenderObject r) {
      if (r is RenderFlex && r.direction == Axis.horizontal) {
        var w = 0.0;
        r.visitChildren((c) => w += (c as RenderBox).size.width);
        if (w > r.size.width + 0.5) {
          // ignore: avoid_print
          print('OVERFLOW ${w - r.size.width}: ${r.debugCreator}');
        }
      }
      r.visitChildren(walk);
    }
    tester.binding.renderViews.forEach(walk);
    fail('$where: ${ex is FlutterError ? ex.toStringDeep() : ex}');
  }
  final buttons = find.byWidgetPredicate(
    (w) => w is ButtonStyleButton || w is AccentButton,
  );
  var checked = 0;
  for (final b in buttons.evaluate()) {
    final texts = find.descendant(
      of: find.byElementPredicate((e) => e == b),
      matching: find.byType(RichText),
    );
    for (final te in texts.evaluate()) {
      final p = te.renderObject! as RenderParagraph;
      final label = p.text.toPlainText();
      final fs = p.text.style?.fontSize ?? 14;
      expect(p.size.height, lessThan(fs * 1.9),
          reason: '$where: "$label" wraps onto a 2nd line');
      expect(p.didExceedMaxLines, isFalse, reason: '$where: "$label" cut');
      checked++;
    }
  }
  expect(checked, greaterThan(0), reason: '$where: no buttons found');
  // AccentButton: the label fits at full size in Roboto (Android).
  for (final e in find.byType(AccentButton).evaluate()) {
    final b = e.widget as AccentButton;
    final width = (e.renderObject! as RenderBox).size.width;
    final room = width - 32 - (b.icon == null ? 0 : 26);
    final tp = TextPainter(
      text: TextSpan(
        text: b.label,
        style: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    expect(tp.width, lessThanOrEqualTo(room),
        reason: '$where: "${b.label}" too long for the button');
  }
}

Future<_FakeSync> _pump(
  WidgetTester tester,
  String lang,
  SyncState state,
  Widget page, {
  bool serverDeployed = false,
}) async {
  final fake = _FakeSync(state, serverDeployed: serverDeployed);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        overrides: [
          appPrefsProvider.overrideWith(() => _FakePrefs(lang)),
          syncControllerProvider.overrideWith(() => fake),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: Scaffold(body: page),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return fake;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final w in const [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.inter(fontWeight: w);
    }
    await GoogleFonts.pendingFonts();
    // Real icon glyphs in the screenshots (tests use a box font otherwise).
    final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
    final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
    // AccentButton labels have no font family, so on Android they use the
    // system font (Roboto); tests draw them in a box font. Their real width
    // is measured with Roboto below.
    final fonts = '$sdk/bin/cache/artifacts/material_fonts';
    for (final family in const ['Roboto']) {
      final loader = FontLoader(family);
      for (final f in const ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold', 'Roboto-Black']) {
        final file = File('$fonts/$f.ttf');
        if (file.existsSync()) {
          loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    }
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360 * 2, 1500 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  for (final lang in S.supported.keys) {
    testWidgets('[$lang] new device: QR reachable, buttons one line',
        (tester) async {
      phone(tester);
      final fake = await _pump(
          tester, lang, const SyncState(), const SyncedDevicesPage());
      final t = S(lang);
      expect(find.byKey(const ValueKey('sync_start_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync_scan_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync_direct_card')), findsNothing);
      _expectButtonsOneLine(tester, '$lang start');
      await _shot(tester, '${lang}_1_new_device');

      // Show QR → confirm (short label, one line).
      await tester.tap(find.byKey(const ValueKey('sync_start_button')));
      await _settle(tester);
      expect(find.text(t('sync_start_ok')), findsOneWidget);
      _expectButtonsOneLine(tester, '$lang start confirm');
      await _shot(tester, '${lang}_2_start_confirm');

      // Relay without the group update: clear message + this phone's QR.
      await tester.tap(find.text(t('sync_start_ok')));
      await _settle(tester);
      expect(find.text(t('sync_err_server')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync_direct_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync_my_qr')), findsOneWidget);
      expect(fake.pairingCodeCalls, greaterThan(0));
      _expectButtonsOneLine(tester, '$lang direct');
      await _shot(tester, '${lang}_3_server_not_updated_direct_qr');
      await tester.pump(const Duration(seconds: 8)); // notice timer
      await _settle(tester);
    });

    testWidgets('[$lang] server deployed: start shows the join QR',
        (tester) async {
      phone(tester);
      await _pump(tester, lang, const SyncState(), const SyncedDevicesPage(),
          serverDeployed: true);
      final t = S(lang);
      await tester.tap(find.byKey(const ValueKey('sync_start_button')));
      await _settle(tester);
      await tester.tap(find.text(t('sync_start_ok')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('sync_invite_qr')), findsOneWidget);
      _expectButtonsOneLine(tester, '$lang invite');
      await _shot(tester, '${lang}_4_admin_invite_qr');
      await tester.tap(find.byKey(const ValueKey('sync_invite_close')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('[$lang] admin with a join request', (tester) async {
      phone(tester);
      await _pump(tester, lang, SyncState(group: _adminGroup()),
          const SyncedDevicesPage());
      expect(find.byKey(const ValueKey('sync_approve_button')), findsOneWidget);
      _expectButtonsOneLine(tester, '$lang admin');
      await _shot(tester, '${lang}_5_admin_list');
      await tester.tap(find.byKey(const ValueKey('sync_leave_button')));
      await _settle(tester);
      // Nov 14: an admin leaving deletes the group for every device.
      final t = S(lang);
      expect(find.text(t('sync_dissolve_q')), findsOneWidget);
      expect(find.text(t('sync_leave_q')), findsNothing);
      _expectButtonsOneLine(tester, '$lang leave confirm');
      await _shot(tester, '${lang}_6_leave_confirm');
    });

    testWidgets('[$lang] admin Leave → Delete dissolves the group',
        (tester) async {
      phone(tester);
      final fake = await _pump(tester, lang, SyncState(group: _adminGroup()),
          const SyncedDevicesPage());
      final t = S(lang);
      await tester.tap(find.byKey(const ValueKey('sync_leave_button')));
      await _settle(tester);
      await tester.tap(find.text(t('sync_dissolve_ok')));
      await _settle(tester);
      expect(fake.dissolveCalls, 1);
      expect(fake.leaveCalls, 0);
    });

    testWidgets('[$lang] normal device: Leave keeps the old text',
        (tester) async {
      phone(tester);
      final member = GroupInfo(
        state: GroupState.active,
        groupId: 'g',
        myId: _other,
        doc: _adminGroup(joins: true).doc,
      );
      final fake = await _pump(
          tester, lang, SyncState(group: member), const SyncedDevicesPage());
      final t = S(lang);
      await tester.tap(find.byKey(const ValueKey('sync_leave_button')));
      await _settle(tester);
      expect(find.text(t('sync_leave_q')), findsOneWidget);
      expect(find.text(t('sync_dissolve_q')), findsNothing);
      _expectButtonsOneLine(tester, '$lang member leave confirm');
      await tester.tap(find.text(t('sync_leave_ok')));
      await _settle(tester);
      expect(fake.leaveCalls, 1);
      expect(fake.dissolveCalls, 0);
    });

    GroupInfo twoAdmins() {
      final base = _adminGroup(joins: false);
      return GroupInfo(
        state: GroupState.active,
        groupId: 'g',
        myId: _me,
        doc: MemberDoc(
          groupId: 'g',
          version: 2,
          epoch: 1,
          issuedAt: 0,
          signer: _me,
          members: [_m(_me, '', 'admin'), _m(_other, 'Counter phone', 'admin')],
        ),
        lastSyncAt: base.lastSyncAt,
      );
    }

    for (final pick in ['leave', 'delete']) {
      testWidgets('[$lang] 2 admins: Leave offers Leave + Delete group ($pick)',
          (tester) async {
        phone(tester);
        final fake = await _pump(tester, lang, SyncState(group: twoAdmins()),
            const SyncedDevicesPage());
        final t = S(lang);
        await tester.tap(find.byKey(const ValueKey('sync_leave_button')));
        await _settle(tester);
        expect(find.byKey(const ValueKey('sync_leave_choice')), findsOneWidget);
        expect(find.text(t('sync_leave_choice_q')), findsOneWidget);
        expect(find.text(t('sync_dissolve_q')), findsNothing);
        expect(find.text(t('sync_delete_group')), findsOneWidget);
        _expectButtonsOneLine(tester, '$lang two-admin leave choice');
        if (pick == 'leave') await _shot(tester, '${lang}_7_two_admin_leave_choice');
        await tester.tap(find.byKey(ValueKey('sync_choice_$pick')));
        await _settle(tester);
        expect(fake.leaveCalls, pick == 'leave' ? 1 : 0);
        expect(fake.dissolveCalls, pick == 'delete' ? 1 : 0);
      });
    }

    testWidgets('[$lang] 2 admins: Cancel does nothing', (tester) async {
      phone(tester);
      final fake = await _pump(tester, lang, SyncState(group: twoAdmins()),
          const SyncedDevicesPage());
      await tester.tap(find.byKey(const ValueKey('sync_leave_button')));
      await _settle(tester);
      await tester.tap(find.text(S(lang)('cancel')).last);
      await _settle(tester);
      expect(find.byKey(const ValueKey('sync_leave_choice')), findsNothing);
      expect(fake.leaveCalls + fake.dissolveCalls, 0);
    });

    testWidgets('[$lang] waiting for approval', (tester) async {
      phone(tester);
      await _pump(
        tester,
        lang,
        const SyncState(group: GroupInfo(state: GroupState.joining)),
        const SyncedDevicesPage(),
      );
      _expectButtonsOneLine(tester, '$lang joining');
      await _shot(tester, '${lang}_7_joining');
    });

    testWidgets('[$lang] trash', (tester) async {
      phone(tester);
      await _pump(tester, lang, SyncState(group: _adminGroup()),
          const SyncTrashPage());
      expect(find.byKey(const ValueKey('sync_restore_all')), findsOneWidget);
      _expectButtonsOneLine(tester, '$lang trash');
      await _shot(tester, '${lang}_8_trash');
      await tester.tap(find.byKey(const ValueKey('sync_empty_trash')));
      await _settle(tester);
      _expectButtonsOneLine(tester, '$lang empty confirm');
      await _shot(tester, '${lang}_9_empty_confirm');
    });

    testWidgets('[$lang] name dialog', (tester) async {
      phone(tester);
      await tester.pumpWidget(RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showSyncNameDialog(ctx, S(lang)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await _settle(tester);
      _expectButtonsOneLine(tester, '$lang name dialog');
      await _shot(tester, '${lang}_10_name_dialog');
    });
  }

  testWidgets('old paired device still waiting: its QR stays visible',
      (tester) async {
    phone(tester);
    await _pump(
      tester,
      'en',
      SyncState(peers: [
        SyncPeer(
          peerId: _other,
          name: 'Counter phone',
          status: 'pending',
          createdAt: DateTime(2026),
        ),
      ]),
      const SyncedDevicesPage(),
    );
    expect(find.byKey(const ValueKey('sync_direct_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_my_qr')), findsOneWidget);
    _expectButtonsOneLine(tester, 'legacy waiting');
    await _shot(tester, 'en_11_old_pairing_waiting');
  });
}
