import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/sync/sync_engine.dart';
import 'package:inventory_app/core/sync/sync_payload.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/features/settings/presentation/synced_devices_page.dart';

import 'sync_test_harness.dart';

/// Nov 11 client review: after pairing both phones the page still showed
/// the "scan each other" hint and ⏳ although it said "Up to date".
void main() {
  late FakeRelay relay;
  late TestDevice a, b;
  var now = DateTime(2026, 11, 11, 10);
  DateTime clock() => now;

  setUp(() async {
    relay = FakeRelay();
    a = await TestDevice.create(relay, clock: clock);
    b = await TestDevice.create(relay, clock: clock);
  });

  Future<List<String>> statuses(TestDevice d) async =>
      [for (final p in await d.engine.peers()) p.status];

  test('normal mutual pairing ends active on both sides', () async {
    await pairDevices(a, b);
    await settle(a, b);
    expect(await statuses(a), ['active']);
    expect(await statuses(b), ['active']);
  });

  test('Erase Data through another engine: identity follows the database',
      () async {
    final before = (await a.engine.identity()).deviceId;
    // forgetSyncForErase() uses its own engine instance on the same DB.
    final eraser = SyncEngine(
      database: () async => a.db,
      transport: relay,
      photoDir: () async => a.photos.path,
    );
    await eraser.forgetEverything();
    final after = (await a.engine.identity()).deviceId;
    expect(after, isNot(before));
    final code = PairingPayload.tryParse(await a.engine.pairingCode())!;
    expect(code.deviceId, after);
  });

  test('pairing right after Erase Data still completes after a restart',
      () async {
    await a.engine.identity(); // cached in the long-lived engine
    final eraser = SyncEngine(
      database: () async => a.db,
      transport: relay,
      photoDir: () async => a.photos.path,
    );
    await eraser.forgetEverything();

    // Pair with the long-lived engine (what the page uses) …
    await pairDevices(a, b);
    await a.engine.syncOnce();

    // … then the app restarts before B synced (new engine, same DB).
    final restarted = SyncEngine(
      database: () async => a.db,
      transport: relay,
      photoDir: () async => a.photos.path,
      clock: clock,
    );
    await b.engine.syncOnce();
    await restarted.syncOnce();
    await b.engine.syncOnce();
    expect(await statuses(b), ['active'], reason: 'no endless ⏳ on B');
    expect([for (final p in await restarted.peers()) p.status], ['active']);

    // Data flows from the restarted phone.
    await a.addItem('x1', 'Milk', at: now);
    await restarted.syncOnce();
    await b.engine.syncOnce();
    expect((await b.item('x1'))?['title'], 'Milk');
  });

  test('removing a device rotates the pairing code (page must refresh it)',
      () async {
    await pairDevices(a, b);
    await settle(a, b);
    final oldCode = await a.engine.pairingCode();
    await a.engine.removePeer((await a.engine.peers()).single.peerId);
    final newCode = await a.engine.pairingCode();
    expect(newCode, isNot(oldCode));

    // Pairing again with the fresh code works on both sides.
    await b.engine.syncOnce(); // B learns A unpaired (410 → removed)
    await b.engine.removePeer((await b.engine.peers()).single.peerId);
    await pairDevices(a, b);
    await settle(a, b);
    expect(await statuses(a), ['active']);
    expect(await statuses(b), ['active']);
  });

  test('a stale code from before the rotation can never pair (why the QR '
      'is rebuilt whenever the device list changes)', () async {
    final c = await TestDevice.create(relay, clock: clock);
    await pairDevices(a, c);
    await settle(a, c);
    final stale = PairingPayload.tryParse(await a.engine.pairingCode())!;
    await a.engine.removePeer((await a.engine.peers()).single.peerId);

    await b.engine.confirmPeer(stale, 'A (old QR)');
    await a.engine.confirmPeer(
        PairingPayload.tryParse(await b.code())!, 'B');
    await settle(a, b);
    expect(await statuses(a), ['pending']);
    expect(await statuses(b), ['pending']);
  });

  group('name dialog', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<Future<String?> Function()> openDialog(WidgetTester tester) async {
      String? result;
      var done = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showSyncNameDialog(ctx, S('en'));
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      return () async {
        expect(done, isTrue);
        return result;
      };
    }

    testWidgets('starts empty; Confirm only after a name is typed',
        (tester) async {
      final result = await openDialog(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('sync_name_field'));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      FilledButton confirm() => tester.widget<FilledButton>(
          find.byKey(const ValueKey('sync_name_confirm')));
      expect(confirm().onPressed, isNull);

      await tester.enterText(field, '   ');
      await tester.pump();
      expect(confirm().onPressed, isNull, reason: 'spaces only');

      await tester.enterText(field, ' Shop iPhone ');
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('sync_name_confirm')));
      await tester.pumpAndSettle();
      expect(await result(), 'Shop iPhone');
    });
  });
}
