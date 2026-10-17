import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/discovery_math.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/discovery/taste_model.dart';
import 'package:hive/hive.dart';

const _episode = MediaItem(
  id: 'podcast_1',
  title: 'Episode 12',
  artist: 'The Show',
  duration: Duration(hours: 1),
  extras: {'isPodcast': true},
);

/// A YouTube Music episode: a video id, but an episode.
const _ytEpisode = MediaItem(
  id: 'ytEpisode01',
  title: 'Episode 3',
  artist: 'Talk Show',
  duration: Duration(hours: 1),
  extras: {'isPodcast': true},
);

const _chapter = MediaItem(
  id: 'lv_b1_1',
  title: 'Chapter 1',
  artist: 'The Author',
  album: 'The Book',
  duration: Duration(minutes: 20),
);

const _song = MediaItem(
  id: 'song1',
  title: 'Song',
  artist: 'Band',
  duration: Duration(minutes: 3),
);

DiscoveryEvent _event(String id, String artist, DiscoverySource source,
        {DiscoveryEventKind kind = DiscoveryEventKind.playEnded}) =>
    DiscoveryEvent(
      videoId: id,
      artistKey: normalizeArtistKey(artist),
      ts: DateTime.now().millisecondsSinceEpoch,
      source: source,
      event: kind,
      fraction: 1,
      title: id,
      artist: artist,
    );

void main() {
  late DiscoveryRepository repo;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_long_form_taste_');
    Hive.init(tmp.path);
    repo = DiscoveryRepository();
    await repo.open();
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test("an episode or a book's chapter isn't music: Stats counts it, taste not",
      () async {
    await Hive.openBox('SongStats');
    await Hive.openBox('DailyStats');
    final discovery = DiscoveryService()
      ..repo = repo
      ..taste = TasteModel(repo);

    await discovery.onMediaChanged(_episode);
    await discovery.onMediaChanged(_ytEpisode,
        positionMs: const Duration(minutes: 50).inMilliseconds);
    await discovery.onMediaChanged(_song,
        positionMs: const Duration(minutes: 40).inMilliseconds);
    await discovery.onMediaChanged(_chapter,
        positionMs: const Duration(minutes: 3).inMilliseconds);
    await discovery.onMediaChanged(null,
        positionMs: const Duration(minutes: 20).inMilliseconds);

    expect(
        repo.recentEvents(limit: 100).map((e) => e.videoId).toSet(), {'song1'});
    expect(repo.affinityOf(normalizeArtistKey('Band')), greaterThan(0));
    for (final artist in ['The Show', 'Talk Show', 'The Author']) {
      expect(repo.affinityOf(normalizeArtistKey(artist)), 0, reason: artist);
    }
    expect(repo.isUnheard('song1'), isFalse);
    for (final id in ['podcast_1', 'ytEpisode01', 'lv_b1_1']) {
      expect(repo.isUnheard(id), isTrue, reason: id);
    }
    // Your listening time still has them.
    final stats = Hive.box('SongStats');
    expect((stats.get('podcast_1') as Map)['seconds'], 50 * 60);
    expect((stats.get('lv_b1_1') as Map)['seconds'], 20 * 60);

    // Liked, saved, downloaded or never to be played: not taste either.
    await discovery.onFavorite(_episode, add: true);
    await discovery.onPlaylistAdd(_ytEpisode);
    await discovery.onDownload(_chapter);
    await discovery.onNeverPlay(_episode);
    expect(
        repo.recentEvents(limit: 100).map((e) => e.videoId).toSet(), {'song1'});
  });

  group('what they left in it before', () {
    test('goes, once: plays, stats, pairings, shows as artists, mix tracks',
        () async {
      for (final e in [
        _event('podcast_1', 'The Show', DiscoverySource.podcast),
        _event('ytEpisode01', 'Talk Show', DiscoverySource.podcast),
        _event('lv_b1_1', 'The Author', DiscoverySource.unknown),
        _event('song1', 'Band', DiscoverySource.search),
        // A show named as a band you also listen to keeps its affinity.
        _event('podcast_2', 'Band', DiscoverySource.podcast),
      ]) {
        await repo.appendEvent(e);
      }
      for (final id in ['podcast_1', 'ytEpisode01', 'lv_b1_1', 'song1']) {
        await repo.recordTrackPlay(id);
      }
      // Played from a show's page: known only by where it was played from.
      await repo.recordTrackPlay('ytEpisode02',
          source: DiscoverySource.podcast);
      await repo.bumpCooccurrence('song1', 'podcast_1');
      await repo.bumpCooccurrence('song1', 'song2');
      for (final artist in ['The Show', 'Talk Show', 'The Author', 'Band']) {
        await repo.bumpAffinity(normalizeArtistKey(artist), 2);
      }
      await repo.saveMix(GeneratedMix(
        id: 'rediscover',
        title: 'Rediscover',
        reason: '',
        kind: MixKind.rediscover,
        tracks: [
          {'videoId': 'podcast_1'},
          {'videoId': 'song1'},
          {'videoId': 'ytEpisode01'},
        ],
        generatedTs: 1,
      ));

      expect(await repo.forgetLongForm(), 4);

      expect(repo.recentEvents(limit: 100).map((e) => e.videoId), ['song1']);
      expect(repo.isUnheard('song1'), isFalse);
      for (final id in ['podcast_1', 'ytEpisode01', 'ytEpisode02', 'lv_b1_1']) {
        expect(repo.isUnheard(id), isTrue, reason: id);
      }
      expect(repo.neighborsOf('song1'), {'song2': 1.0});
      expect(repo.neighborsOf('podcast_1'), isEmpty);
      expect(repo.topAffinities().keys.toSet(), {normalizeArtistKey('Band')});
      expect(repo.getMix('rediscover')!.tracks.map((t) => t['videoId']),
          ['song1']);

      // Done once: what's played since is left alone.
      await repo.appendEvent(
          _event('podcast_3', 'The Show', DiscoverySource.podcast));
      expect(await repo.forgetLongForm(), 0);
      expect(repo.eventCount, 2);
    });

    test("Stats' episodes and chapters, from before plays were logged",
        () async {
      final stats = await Hive.openBox('SongStats');
      await stats.putAll({
        'ytEpisode01': {'artist': 'Talk Show', 'plays': 3, 'kind': 'podcast'},
        'abs_1': {'artist': 'The Author', 'plays': 2},
        'song1': {'artist': 'Band', 'plays': 4},
      });
      // The first backfill now seeds music only.
      await repo.backfillFromSongStats(stats);
      expect(repo.topAffinities().keys.toSet(), {normalizeArtistKey('Band')});
      expect(repo.isUnheard('ytEpisode01'), isTrue);

      // As an earlier one did: its shows go, and the episode's plays, though
      // it was played from search results.
      for (final id in ['ytEpisode01', 'abs_1']) {
        await repo.recordTrackPlay(id);
      }
      await repo.appendEvent(
          _event('ytEpisode01', 'Talk Show', DiscoverySource.search));
      await repo.bumpAffinity(normalizeArtistKey('Talk Show'), 1);
      expect(await repo.forgetLongForm(songStats: stats), 1);
      expect(repo.topAffinities().keys.toSet(), {normalizeArtistKey('Band')});
      expect(repo.eventCount, 0);
      expect(repo.isUnheard('ytEpisode01'), isTrue);
      expect(repo.isUnheard('abs_1'), isTrue);
      expect(repo.isUnheard('song1'), isFalse);
    });
  });

  test('Rediscover is songs only', () async {
    final old = DateTime.now().subtract(const Duration(days: 200));
    for (final id in ['podcast_1', 'song1', 'ytEpisode01']) {
      await repo.recordTrackPlay(id, now: old);
      await repo.recordTrackPlay(id,
          now: old,
          source: id == 'ytEpisode01' ? DiscoverySource.podcast : null);
    }
    expect(repo.rediscoverIds(), ['song1']);
  });
}
