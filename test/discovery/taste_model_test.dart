import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:harmonymusic/services/discovery/discovery_math.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/discovery/taste_model.dart';

void main() {
  late DiscoveryRepository repo;
  late TasteModel taste;
  late String tmpDir;

  setUpAll(() async {
    tmpDir =
        '${Directory.systemTemp.path}/riff_disc_test_${DateTime.now().microsecondsSinceEpoch}';
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
    taste = TasteModel(repo);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await Directory(tmpDir).delete(recursive: true);
    } catch (_) {}
  });

  test('full listen raises affinity; 3 quick skips lower it', () async {
    await taste.logPlayEnded(
      videoId: 'v1',
      artist: 'Phonk King',
      title: 'Drift',
      source: DiscoverySource.userClick,
      listenedMs: 180000,
      totalMs: 200000,
    );
    final afterListen = repo.affinityOf(normalizeArtistKey('Phonk King'));
    expect(afterListen, greaterThan(1.0));

    for (var i = 0; i < 3; i++) {
      await taste.logPlayEnded(
        videoId: 'v$i',
        artist: 'Phonk King',
        title: 'Skip me $i',
        source: DiscoverySource.radio,
        listenedMs: 3000,
        totalMs: 200000,
      );
    }
    final afterSkips = repo.affinityOf(normalizeArtistKey('Phonk King'));
    expect(afterSkips, lessThan(afterListen));
    expect(repo.skipRateOf(normalizeArtistKey('Phonk King')), greaterThan(0.4));
  });

  test('unknown duration is neutral, not a full listen', () async {
    // Track whose stream never resolved: position/duration never advanced, so
    // totalMs is 0. This must not be scored as a 100% listen.
    await taste.logPlayEnded(
      videoId: 'v',
      artist: 'Ghost',
      title: 'T',
      source: DiscoverySource.userClick,
      listenedMs: 30000,
      totalMs: 0,
    );
    expect(repo.affinityOf(normalizeArtistKey('Ghost')), 0.0);
    final ev = repo.recentEvents(limit: 10).last;
    expect(ev.event, DiscoveryEventKind.playEnded);
    expect(ev.fraction, isNull);
  });

  test('unknown duration under 10s is still a quick skip', () async {
    await taste.logPlayEnded(
      videoId: 'v',
      artist: 'Ghost Two',
      title: 'T',
      source: DiscoverySource.userClick,
      listenedMs: 4000,
      totalMs: 0,
    );
    expect(repo.affinityOf(normalizeArtistKey('Ghost Two')),
        closeTo(AffinityWeights.quickSkip, 0.01));
    expect(repo.recentEvents(limit: 10).last.event,
        DiscoveryEventKind.quickSkip);
  });

  test('favorite bumps affinity strongly', () async {
    await taste.logFavorite('vid', 'Artist X', 'Song', add: true);
    expect(repo.affinityOf(normalizeArtistKey('Artist X')),
        closeTo(AffinityWeights.favorite, 0.01));
  });

  test('never play applies mild artist penalty', () async {
    await taste.logPlayEnded(
      videoId: 'v',
      artist: 'Noisy',
      title: 'T',
      source: DiscoverySource.userClick,
      listenedMs: 200000,
      totalMs: 200000,
    );
    final before = repo.affinityOf(normalizeArtistKey('Noisy'));
    await taste.logNeverPlay('v', 'Noisy', 'T');
    final after = repo.affinityOf(normalizeArtistKey('Noisy'));
    expect(after, lessThan(before));
  });

  test('co-occurrence within session', () async {
    await taste.logPlayStarted(
      videoId: 'a',
      artist: 'A',
      title: '1',
      source: DiscoverySource.userClick,
    );
    await taste.logPlayStarted(
      videoId: 'b',
      artist: 'B',
      title: '2',
      source: DiscoverySource.queue,
    );
    final neigh = repo.neighborsOf('a');
    expect(neigh.containsKey('b'), isTrue);
    expect(neigh['b']!, greaterThan(0));
  });

  test('impressions mark shownRecently', () async {
    await repo.logImpression('vid1', DiscoverySurface.home);
    expect(repo.shownRecently('vid1'), isTrue);
    expect(repo.shownRecently('vid2'), isFalse);
  });

  test('scoreCandidate hard-drops banned via negative infinity flag', () {
    final s = taste.scoreCandidate(
      videoId: 'x',
      artistKey: 'a',
      sourceConfidence: 1,
      isBanned: true,
    );
    expect(s.isNegative, isTrue);
    expect(s.isInfinite, isTrue);
  });

  test('rediscover finds quiet high-play tracks', () async {
    final old = DateTime.now().subtract(const Duration(days: 120));
    await repo.recordTrackPlay('old1', now: old, weight: 5);
    final box = Hive.box(DiscoveryBoxes.trackStats);
    await box.put('old1', {
      'decayedPlays': 5.0,
      'lastPlayedTs': old.millisecondsSinceEpoch,
      'lifetimePlays': 5,
    });
    await box.put('new1', {
      'decayedPlays': 5.0,
      'lastPlayedTs': DateTime.now().millisecondsSinceEpoch,
      'lifetimePlays': 5,
    });
    final ids = repo.rediscoverIds(quietDays: 90, minLifetimePlays: 2);
    expect(ids, contains('old1'));
    expect(ids, isNot(contains('new1')));
  });
}
