import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';

void main() {
  late DiscoveryRepository repo;
  late String tmpDir;

  setUpAll(() async {
    tmpDir =
        '${Directory.systemTemp.path}/riff_disc_repo_test_${DateTime.now().microsecondsSinceEpoch}';
    await Directory(tmpDir).create(recursive: true);
    Hive.init(tmpDir);
  });

  setUp(() async {
    for (final name in DiscoveryBoxes.all) {
      final box = await Hive.openBox(name);
      await box.clear();
    }
    repo = DiscoveryRepository();
    await repo.open();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await Directory(tmpDir).delete(recursive: true);
    } catch (_) {}
  });

  int hubEdgesInBox(String id) => Hive.box(DiscoveryBoxes.cooccurrence)
      .keys
      .map((k) => k.toString())
      .where((k) => k.split('|').contains(id))
      .length;

  test('co-occurrence cap keeps maxNeighbors strongest edges', () async {
    const max = DiscoveryRepository.maxNeighbors;
    // n0..n{max+9}; weight grows with index so n0..n9 are the weakest.
    for (var i = 0; i < max + 10; i++) {
      await repo.bumpCooccurrence('hub', 'n$i', weight: i + 1.0);
    }
    final neigh = repo.neighborsOf('hub', limit: 1000);
    expect(neigh.length, max);
    expect(hubEdgesInBox('hub'), max);
    for (var i = 0; i < 10; i++) {
      expect(neigh.containsKey('n$i'), isFalse, reason: 'n$i is weakest');
    }
    expect(neigh.containsKey('n${max + 9}'), isTrue);
    // Dropped edges disappear from the other endpoint too.
    expect(repo.neighborsOf('n0'), isEmpty);
    expect(repo.neighborsOf('n${max + 9}'), {'hub': max + 10.0});
  });

  test('just-bumped edge survives the cap even when weakest', () async {
    const max = DiscoveryRepository.maxNeighbors;
    for (var i = 0; i < max; i++) {
      await repo.bumpCooccurrence('hub', 'n$i', weight: 5);
    }
    await repo.bumpCooccurrence('hub', 'fresh', weight: 0.5);
    final neigh = repo.neighborsOf('hub', limit: 1000);
    expect(neigh.length, max);
    expect(neigh['fresh'], 0.5);
  });

  test('neighborsOf is sorted, limited, and matches a rebuilt index', () async {
    await repo.bumpCooccurrence('a', 'b', weight: 1);
    await repo.bumpCooccurrence('c', 'a', weight: 3);
    await repo.bumpCooccurrence('a', 'd', weight: 2);
    await repo.bumpCooccurrence('a', 'b', weight: 1.5);
    expect(repo.neighborsOf('a').keys.toList(), ['c', 'b', 'd']);
    expect(repo.neighborsOf('a', limit: 2), {'c': 3.0, 'b': 2.5});

    final fresh = DiscoveryRepository();
    await fresh.open();
    expect(fresh.neighborsOf('a'), repo.neighborsOf('a'));
    expect(fresh.neighborsOf('c'), {'a': 3.0});
  });

  test('resetTasteModel clears the neighbor index', () async {
    await repo.bumpCooccurrence('a', 'b');
    await repo.resetTasteModel();
    expect(repo.neighborsOf('a'), isEmpty);
    await repo.bumpCooccurrence('a', 'c');
    expect(repo.neighborsOf('a'), {'c': 1.0});
  });

  test('pruneAuxiliary trims overgrown graph, old impressions, expired cache',
      () async {
    const max = DiscoveryRepository.maxNeighbors;
    final cooc = Hive.box(DiscoveryBoxes.cooccurrence);
    // Written directly, as by builds where the cap never fired.
    await cooc.putAll({
      for (var i = 0; i < max + 50; i++)
        'hub|x${i.toString().padLeft(3, '0')}': i + 1.0,
    });

    final now = DateTime(2026, 9, 30, 12);
    final ms = now.millisecondsSinceEpoch;
    const day = 86400000;
    final imp = Hive.box(DiscoveryBoxes.impressions);
    await imp.putAll({
      'old|home': ms - 40 * day,
      'new|home': ms - 2 * day,
      'old|*': ms - 400 * day,
      'mid|*': ms - 200 * day,
    });

    final cache = Hive.box(DiscoveryBoxes.apiCache);
    await cache.putAll({
      'expired': {'json': 1, 'expiresTs': ms - 1},
      'valid': {'json': 2, 'expiresTs': ms + day},
    });

    await repo.pruneAuxiliary(now: now);

    expect(cooc.length, max);
    expect(repo.neighborsOf('hub', limit: 1000).length, max);
    expect(cooc.containsKey('hub|x000'), isFalse);
    expect(cooc.containsKey('hub|x${max + 49}'), isTrue);

    expect(imp.keys.toSet(), {'new|home', 'mid|*'});
    expect(cache.keys.toSet(), {'valid'});
  });

  test('logImpressions writes surface and global entries', () async {
    final now = DateTime(2026, 9, 30);
    await repo.logImpressions(['a', 'b'], 'home', now: now);
    final ts = now.millisecondsSinceEpoch;
    expect(repo.lastImpressionTs('a', surface: 'home'), ts);
    expect(repo.lastImpressionTs('b'), ts);
    expect(Hive.box(DiscoveryBoxes.impressions).length, 4);
    await repo.logImpressions(const [], 'home');
    expect(Hive.box(DiscoveryBoxes.impressions).length, 4);
  });

  test('pruneEvents drops aged events and caps the total', () async {
    final events = Hive.box(DiscoveryBoxes.events);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final oldTs = DateTime.now()
        .subtract(DiscoveryRepository.maxEventAge + const Duration(days: 1))
        .millisecondsSinceEpoch;
    await events.addAll([
      for (var i = 0; i < 5; i++) {'ts': oldTs, 'videoId': 'old$i'},
      for (var i = 0; i < DiscoveryRepository.maxEvents + 7; i++)
        {'ts': nowMs, 'videoId': 'v$i'},
    ]);
    await repo.pruneEvents();
    expect(events.length, DiscoveryRepository.maxEvents);
    expect(repo.eventCount, DiscoveryRepository.maxEvents);
    final ids = events.values.map((e) => (e as Map)['videoId']).toList();
    expect(ids.first, 'v7');
    expect(ids.any((v) => '$v'.startsWith('old')), isFalse);
  });

  test('deleteMixes ignores unknown ids', () async {
    final mixes = Hive.box(DiscoveryBoxes.mixes);
    await mixes.put('daily_mix_5', {'id': 'daily_mix_5'});
    await repo.deleteMixes(['daily_mix_5', 'nope']);
    expect(mixes.isEmpty, isTrue);
  });
}
