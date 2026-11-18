import 'package:flutter_test/flutter_test.dart';
import 'sync_test_harness.dart';

/// The 5 s poll must not re-read and hash the whole database when nothing
/// changed, but must still pick up any local write right away.
void main() {
  late FakeRelay relay;
  late TestDevice a, b;
  var now = DateTime(2026, 11, 11, 12);
  DateTime clock() => now = now.add(const Duration(seconds: 1));

  Future<int> records(TestDevice d) async =>
      (await d.db.rawQuery('SELECT COUNT(*) AS n FROM sync_records'))
          .first['n']! as int;

  setUp(() async {
    relay = FakeRelay();
    a = await TestDevice.create(relay, clock: clock);
    b = await TestDevice.create(relay, clock: clock);
    await a.addItem('i1', 'Bread', at: DateTime(2026, 1, 1));
    await pairDevices(a, b);
    await settle(a, b);
  });

  test('quick poll still sends a local edit made without any provider',
      () async {
    await a.engine.syncOnce(skipUnchangedScan: true);
    await a.addItem('i2', 'Milk', at: DateTime(2026, 11, 11));
    await a.engine.syncOnce(skipUnchangedScan: true);
    await b.engine.syncOnce(skipUnchangedScan: true);
    expect((await b.item('i2'))?['title'], 'Milk');
  });

  test('quick poll applies remote changes and keeps them recorded', () async {
    await b.db.update('inventory_items', {'title': 'Brot',
        'updated_at': DateTime(2026, 11, 11, 13).toIso8601String()},
        where: 'id = ?', whereArgs: ['i1']);
    await b.engine.syncOnce(skipUnchangedScan: true);
    await a.engine.syncOnce(skipUnchangedScan: true);
    expect((await a.item('i1'))?['title'], 'Brot');
    // Nothing bounces back as a "new" local edit afterwards.
    final before = await records(a);
    final r = await a.engine.syncOnce(skipUnchangedScan: true);
    expect(r.pushed, 0);
    expect(await records(a), before);
  });

  test('device whose partner unpaired stops scanning', () async {
    await a.db.update('sync_peers', {'status': 'removed'});
    final before = await records(a);
    await a.addItem('i3', 'Eggs', at: DateTime(2026, 11, 11));
    final r = await a.engine.syncOnce();
    expect(r.ok, isTrue);
    expect(await records(a), before);
  });
}
