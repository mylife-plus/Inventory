import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/media/local_image_store.dart';
import 'package:inventory_app/data/reset/app_reset.dart';
import 'package:inventory_app/data/resale_draft.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Reset App clears photos/temp/receipt draft; keeps settings prefs + DB file',
      () async {
    final docs = await Directory.systemTemp.createTemp('reset_docs');
    final tmp = await Directory.systemTemp.createTemp('reset_tmp');
    final dbFile = File(p.join(docs.path, 'inventory_app.db'));
    await dbFile.writeAsString('shop-db-placeholder');
    final photos = Directory(p.join(docs.path, LocalImageStore.folder));
    await photos.create();
    await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1, 2, 3]);
    await File(
      p.join(tmp.path, 'Turnover_2026-01-01_2026-10-19.xlsx'),
    ).writeAsBytes([1]);

    SharedPreferences.setMockInitialValues({
      'locale': 'de',
      'dark_mode': false,
      'pin_lock': true,
      'prefs_setup_done': true,
      'qr_labels_per_page': 4,
      'receipt_paper': 'a4',
      ResaleDraftNotifier.prefKey: '{"saleId":"s1"}',
    });
    final prefs = await SharedPreferences.getInstance();

    await AppReset.wipeArtifacts(docs: docs, temp: tmp, prefs: prefs);

    expect(await dbFile.exists(), isTrue);
    expect(await dbFile.readAsString(), 'shop-db-placeholder');
    expect(await photos.list().toList(), isEmpty);
    expect(await tmp.list().toList(), isEmpty);

    expect(prefs.getString('locale'), 'de');
    expect(prefs.getBool('dark_mode'), isFalse);
    expect(prefs.getBool('pin_lock'), isTrue);
    expect(prefs.getBool('prefs_setup_done'), isTrue);
    expect(prefs.getInt('qr_labels_per_page'), 4);
    expect(prefs.getString('receipt_paper'), 'a4');
    expect(prefs.containsKey(ResaleDraftNotifier.prefKey), isFalse);

    await docs.delete(recursive: true);
    await tmp.delete(recursive: true);
  });

  test('Reset App wording in all languages', () {
    for (final code in S.supported.keys) {
      for (final k in [
        'erase_all',
        'reset_app_title',
        'reset_app_body',
        'reset_action',
      ]) {
        expect(S(code)(k), isNot(k), reason: '$code $k');
      }
    }
    expect(S('en')('erase_all'), 'Reset App');
    expect(S('en')('reset_app_title'), 'Reset App');
    expect(
      S('en')('reset_app_body'),
      'All app data, including sales, customers, items, and receipts, '
          'will be permanently erased. The app will be reset. '
          'This action cannot be undone.',
    );
    for (final code in S.supported.keys) {
      final body = S(code)('reset_app_body').toLowerCase();
      expect(body.contains('shop'), isFalse, reason: '$code must not erase shop');
      expect(body.contains('settings'), isFalse, reason: '$code en');
      expect(body.contains('einstellungen'), isFalse, reason: '$code de');
      expect(body.contains('ajustes'), isFalse, reason: '$code es');
      expect(body.contains('réglages'), isFalse, reason: '$code fr');
      expect(body.contains('definições'), isFalse, reason: '$code pt');
    }
  });
}
