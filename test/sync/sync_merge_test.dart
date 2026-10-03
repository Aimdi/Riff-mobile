import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/sync/sync_merge.dart';

SyncRecord live(int t, String dev, Map<String, dynamic> data,
        {Map<String, dynamic> extra = const {}}) =>
    SyncRecord(updatedAt: t, device: dev, data: data, extra: extra);

SyncRecord dead(int t, String dev) =>
    SyncRecord.tombstone(updatedAt: t, device: dev);

const day = 24 * 60 * 60 * 1000;
const now = 1767225600000;

/// One device in a simulated sync: its data and its ledger.
class Device {
  Device(this.id);
  final String id;
  Map<String, LocalItem> items = {};
  Map<String, LedgerEntry> ledger = {};

  /// Sync against [server] the way WebDavSyncService does, returning the
  /// new server records.
  Map<String, SyncRecord> sync(Map<String, SyncRecord> server, int at) {
    final local =
        localRecords(items: items, ledger: ledger, device: id, nowMs: at);
    final m = mergeRecords(local, server, nowMs: at);
    for (final id in m.localChanges(local)) {
      final w = m.winners[id]!;
      if (w.deleted) {
        items.remove(id);
      } else {
        items[id] = LocalItem(w.data!);
      }
    }
    ledger = nextLedger(m.winners, items, nowMs: at);
    return m.merged;
  }
}

void main() {
  group('last writer wins', () {
    test('later updatedAt wins', () {
      expect(
          compareRecords(live(2, 'a', {}), live(1, 'b', {})), greaterThan(0));
      expect(compareRecords(live(1, 'z', {}), live(2, 'a', {})), lessThan(0));
    });

    test('a tombstone beats a live record at the same time', () {
      expect(compareRecords(dead(5, 'a'), live(5, 'z', {})), greaterThan(0));
    });

    test('then the larger device id', () {
      expect(
          compareRecords(live(5, 'b', {}), live(5, 'a', {})), greaterThan(0));
    });

    test('merging is order-independent', () {
      final a = {
        'x': live(10, 'a', {'v': 1}),
        'y': dead(now - 20, 'a'),
        'z': live(7, 'a', {'v': 'a'}),
      };
      final b = {
        'x': live(11, 'b', {'v': 2}),
        'y': live(now - 20, 'b', {'v': 3}),
        'z': live(7, 'b', {'v': 'b'}),
        'w': live(1, 'b', {}),
      };
      final ab = mergeRecords(a, b, nowMs: now).merged;
      final ba = mergeRecords(b, a, nowMs: now).merged;
      expect(ab.keys.toSet(), ba.keys.toSet());
      for (final k in ab.keys) {
        expect(ab[k]!.sameAs(ba[k]!), isTrue, reason: k);
      }
      expect(ab['x']!.data, {'v': 2});
      expect(ab['y']!.deleted, isTrue);
      expect(ab['z']!.data, {'v': 'b'});
    });

    test('records on one side only are kept', () {
      final m = mergeRecords({'a': live(1, 'd', {})}, {'b': live(1, 'd', {})},
          nowMs: now);
      expect(m.merged.keys, unorderedEquals(['a', 'b']));
      expect(m.remoteChanged, isTrue);
      expect(m.localChanges({'a': live(1, 'd', {})}), {'b'});
    });

    test('nothing to write when the remote already has the result', () {
      final r = {
        'a': live(3, 'd', {'v': 1})
      };
      final m = mergeRecords({
        'a': live(3, 'd', {'v': 1})
      }, r, nowMs: now);
      expect(m.remoteChanged, isFalse);
      expect(
          m.localChanges({
            'a': live(3, 'd', {'v': 1})
          }),
          isEmpty);
    });

    test('the same write keeps the remote copy and its unknown fields', () {
      final remote = live(3, 'd', {'v': 1, 'future': true},
          extra: {'note': 'from a newer app'});
      final m = mergeRecords({
        'a': live(3, 'd', {'v': 1})
      }, {
        'a': remote
      }, nowMs: now);
      expect(identical(m.merged['a'], remote), isTrue);
      expect(m.remoteChanged, isFalse);
      // Same version: nothing to rewrite locally either.
      expect(
          m.localChanges({
            'a': live(3, 'd', {'v': 1})
          }),
          isEmpty);
    });

    test('a remote tombstone deletes locally', () {
      final local = {'a': live(3, 'd', {})};
      final m = mergeRecords(local, {'a': dead(4, 'e')}, nowMs: now);
      expect(m.localChanges(local), {'a'});
      expect(m.winners['a']!.deleted, isTrue);
    });

    test('a tombstone for something we never had changes nothing locally', () {
      final m = mergeRecords({}, {'a': dead(4, 'e')}, nowMs: now);
      expect(m.localChanges({}), isEmpty);
    });
  });

  group('tombstone expiry', () {
    test('tombstones older than 180 days leave the file', () {
      final old = dead(now - 181 * day, 'a');
      final fresh = dead(now - 10 * day, 'a');
      final m = mergeRecords({}, {'old': old, 'fresh': fresh}, nowMs: now);
      expect(m.merged.keys, ['fresh']);
      expect(m.remoteChanged, isTrue);
    });

    test('an expired tombstone still deletes an older live copy', () {
      final local = {'a': live(now - 200 * day, 'a', {})};
      final m =
          mergeRecords(local, {'a': dead(now - 190 * day, 'b')}, nowMs: now);
      expect(m.localChanges(local), {'a'});
      expect(m.merged, isEmpty);
    });
  });

  group('local changes since the last sync', () {
    test('unchanged records keep the ledger version', () {
      const item = LocalItem({'v': 1});
      final r = localRecords(items: {
        'a': item
      }, ledger: {
        'a': LedgerEntry(
            updatedAt: 50, device: 'other', hash: dataHash({'v': 1}))
      }, device: 'me', nowMs: now)['a']!;
      expect(r.updatedAt, 50);
      expect(r.device, 'other');
    });

    test('a changed record is stamped with its edit time, by us', () {
      final r = localRecords(items: {
        'a': const LocalItem({'v': 2}, editedAt: 900)
      }, ledger: {
        'a': LedgerEntry(updatedAt: 50, device: 'o', hash: dataHash({'v': 1}))
      }, device: 'me', nowMs: now)['a']!;
      expect(r.updatedAt, 900);
      expect(r.device, 'me');
    });

    test('a changed record without an edit time gets now', () {
      final r = localRecords(items: {
        'a': const LocalItem({'v': 2})
      }, ledger: {
        'a': LedgerEntry(updatedAt: 50, device: 'o', hash: dataHash({'v': 1}))
      }, device: 'me', nowMs: now)['a']!;
      expect(r.updatedAt, now);
    });

    test('a change is always later than the version it replaces', () {
      final r = localRecords(items: {
        'a': const LocalItem({'v': 2}, editedAt: 10)
      }, ledger: {
        'a': LedgerEntry(updatedAt: 50, device: 'o', hash: dataHash({'v': 1}))
      }, device: 'me', nowMs: now)['a']!;
      expect(r.updatedAt, 51);
    });

    test('on the first sync, unknown edit times are 0', () {
      final r = localRecords(items: {
        'a': const LocalItem({'v': 1})
      }, ledger: const {}, device: 'me', nowMs: now)['a']!;
      expect(r.updatedAt, 0);
    });

    test('something gone since the last sync becomes a tombstone', () {
      final r = localRecords(items: const {}, ledger: {
        'a': const LedgerEntry(updatedAt: 50, device: 'o', hash: 'x')
      }, device: 'me', nowMs: now)['a']!;
      expect(r.deleted, isTrue);
      expect(r.updatedAt, now);
      expect(r.device, 'me');
    });

    test('a known tombstone is kept as it was', () {
      final r = localRecords(items: const {}, ledger: {
        'a': const LedgerEntry(updatedAt: 70, device: 'o', deleted: true)
      }, device: 'me', nowMs: now)['a']!;
      expect(r.deleted, isTrue);
      expect(r.updatedAt, 70);
      expect(r.device, 'o');
    });

    test('the ledger leaves out what the app could not take in', () {
      final l = nextLedger({
        'kept': live(5, 'a', {'v': 1}),
        'failed': live(6, 'a', {'v': 2}),
        'gone': dead(now - 7, 'a'),
        'stillHere': dead(now - 8, 'a'),
      }, {
        'kept': const LocalItem({'v': 1}),
        'stillHere': const LocalItem({}),
      }, nowMs: now);
      expect(l.keys, unorderedEquals(['kept', 'gone']));
      expect(l['kept']!.hash, dataHash({'v': 1}));
      expect(l['gone']!.deleted, isTrue);
    });

    test('ledger entries survive storage', () {
      const e =
          LedgerEntry(updatedAt: 9, device: 'd', hash: 'h', deleted: false);
      final back = LedgerEntry.fromJson(e.toJson())!;
      expect(back.updatedAt, 9);
      expect(back.device, 'd');
      expect(back.hash, 'h');
      expect(back.deleted, isFalse);
    });
  });

  group('two devices', () {
    test('a fresh device takes the server, and adds its own', () {
      var server = <String, SyncRecord>{};
      final a = Device('a')
        ..items = {
          'show1': const LocalItem({'t': 'One'}, editedAt: 100),
          'show2': const LocalItem({'t': 'Two'}, editedAt: 100),
        };
      server = a.sync(server, now);
      final b = Device('b')
        ..items = {
          'show3': const LocalItem({'t': 'Three'})
        };
      server = b.sync(server, now + 1000);
      expect(b.items.keys, unorderedEquals(['show1', 'show2', 'show3']));
      server = a.sync(server, now + 2000);
      expect(a.items.keys, unorderedEquals(['show1', 'show2', 'show3']));
    });

    test('a deletion on one device reaches the other', () {
      var server = <String, SyncRecord>{};
      final a = Device('a')
        ..items = {
          'x': const LocalItem({'v': 1}, editedAt: 10)
        };
      server = a.sync(server, now);
      final b = Device('b');
      server = b.sync(server, now + 1);
      expect(b.items.containsKey('x'), isTrue);

      a.items.remove('x');
      server = a.sync(server, now + 2);
      expect(server['x']!.deleted, isTrue);
      server = b.sync(server, now + 3);
      expect(b.items.containsKey('x'), isFalse);
      // And it stays gone after more syncs.
      server = b.sync(server, now + 4);
      server = a.sync(server, now + 5);
      expect(a.items.containsKey('x'), isFalse);
      expect(b.items.containsKey('x'), isFalse);
    });

    test('the later edit wins on both devices', () {
      var server = <String, SyncRecord>{};
      final a = Device('a')
        ..items = {
          'ep': const LocalItem({'pos': 10}, editedAt: 10)
        };
      server = a.sync(server, now);
      final b = Device('b');
      server = b.sync(server, now + 1);

      a.items['ep'] = const LocalItem({'pos': 300}, editedAt: now + 100);
      b.items['ep'] = const LocalItem({'pos': 900}, editedAt: now + 200);
      server = a.sync(server, now + 300);
      server = b.sync(server, now + 400);
      server = a.sync(server, now + 500);
      expect(a.items['ep']!.data, {'pos': 900});
      expect(b.items['ep']!.data, {'pos': 900});
    });

    test('a sync with no changes writes nothing', () {
      var server = <String, SyncRecord>{};
      final a = Device('a')
        ..items = {
          'x': const LocalItem({'v': 1}, editedAt: 10)
        };
      server = a.sync(server, now);
      final local = localRecords(
          items: a.items, ledger: a.ledger, device: 'a', nowMs: now + 9);
      final m = mergeRecords(local, server, nowMs: now + 9);
      expect(m.remoteChanged, isFalse);
      expect(m.localChanges(local), isEmpty);
    });

    test('taking in a remote version is not mistaken for a local edit', () {
      var server = <String, SyncRecord>{};
      final a = Device('a')
        ..items = {
          'x': const LocalItem({'v': 1}, editedAt: 10)
        };
      server = a.sync(server, now);
      final b = Device('b');
      server = b.sync(server, now + 1);
      // b re-reads what it took in: same version as the server.
      final local = localRecords(
          items: b.items, ledger: b.ledger, device: 'b', nowMs: now + 2);
      expect(local['x']!.sameVersion(server['x']!), isTrue);
    });
  });

  group('collection files', () {
    test('round trip, with unknown fields kept', () {
      final f = SyncFile(
        collection: 'podcast.episodes',
        records: {
          'a': live(5, 'd', {'positionMs': 1000}, extra: {'x': 1}),
          'b': dead(6, 'd'),
        },
        extra: {'generator': 'riff-desktop'},
      );
      final back = SyncFile.decode(f.encode(), collection: 'podcast.episodes');
      expect(back.version, syncFormatVersion);
      expect(back.extra, {'generator': 'riff-desktop'});
      expect(back.records['a']!.data, {'positionMs': 1000});
      expect(back.records['a']!.extra, {'x': 1});
      expect(back.records['b']!.deleted, isTrue);
      expect(back.records['b']!.data, isNull);
    });

    test('anything else is refused', () {
      expect(() => SyncFile.decode('not json', collection: 'c'),
          throwsFormatException);
      expect(() => SyncFile.decode('{"records": {}}', collection: 'c'),
          throwsFormatException);
      expect(() => SyncFile.decode('{"format": "riff-sync"}', collection: 'c'),
          throwsFormatException);
    });

    test('broken records are skipped, not fatal', () {
      final f = SyncFile.decode(
          '{"format":"riff-sync","version":1,"records":'
          '{"a":{"updatedAt":1},"b":{"updatedAt":2,"device":"d","data":{}}}}',
          collection: 'c');
      expect(f.records.keys, ['b']);
    });

    test('a newer major version is not written', () {
      expect(syncVersionSupported(syncFormatVersion), isTrue);
      expect(syncVersionSupported(syncFormatVersion + 1), isFalse);
    });

    test('canonical JSON ignores key order', () {
      expect(
          canonicalJson({
            'b': 1,
            'a': {'d': 2, 'c': 3}
          }),
          canonicalJson({
            'a': {'c': 3, 'd': 2},
            'b': 1
          }));
      expect(dataHash({'a': 1}), isNot(dataHash({'a': 2})));
    });
  });
}
