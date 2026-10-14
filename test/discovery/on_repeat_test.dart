import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/candidate_sources.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/discovery/mix_generator.dart';
import 'package:harmonymusic/services/discovery/taste_model.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends MusicServices {}

final _now = DateTime(2026, 10, 14, 12);

/// [id] played through [times] times, [daysAgo] days back.
Future<void> _played(DiscoveryRepository repo, String id,
    {int times = 1,
    int daysAgo = 1,
    DiscoveryEventKind kind = DiscoveryEventKind.playEnded}) async {
  for (var i = 0; i < times; i++) {
    await repo.appendEvent(DiscoveryEvent(
      videoId: id,
      artistKey: 'artist $id',
      ts: _now
          .subtract(Duration(days: daysAgo, minutes: i))
          .millisecondsSinceEpoch,
      source: DiscoverySource.search,
      event: kind,
      title: 'Song $id',
      artist: 'Artist $id',
    ));
  }
}

void main() {
  late Directory tmp;
  late DiscoveryRepository repo;
  late MixGenerator mixes;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_on_repeat_');
    Hive.init(tmp.path);
    repo = DiscoveryRepository();
    await repo.open();
    mixes = MixGenerator(
        repo: repo,
        taste: TasteModel(repo),
        sources: CandidateSources(music: _FakeMusic(), repo: repo));
  });

  tearDown(() async {
    BanServiceSafe.setBanHook(null);
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test("the songs you've played most in the last 30 days", () async {
    await _played(repo, 'old0000000a', times: 9, daysAgo: 40);
    await _played(repo, 'twice00000a', times: 2, daysAgo: 20);
    await _played(repo, 'thrice0000a', times: 3, daysAgo: 10);
    await _played(repo, 'twiceNow00a', times: 2);
    await _played(repo, 'once000000a');
    // Skips and plays started aren't plays through.
    await _played(repo, 'skipped000a', times: 4, kind: DiscoveryEventKind.skip);
    await _played(repo, 'started000a',
        times: 4, kind: DiscoveryEventKind.playStarted);
    await _played(repo, 'podcast_1', times: 5);

    expect(repo.onRepeatIds(now: _now),
        ['thrice0000a', 'twiceNow00a', 'twice00000a']);
    expect(repo.onRepeatIds(now: _now, limit: 1), ['thrice0000a']);
  });

  group('On Repeat', () {
    Future<void> sixOnRepeat() async {
      for (var i = 0; i < 6; i++) {
        await _played(repo, 'song00000${i}a', times: 8 - i);
      }
    }

    test('your songs as Riff keeps them, else with their YouTube art',
        () async {
      await sixOnRepeat();
      final fav = await Hive.openBox('LIBFAV');
      await fav.put('song000000a', {
        'videoId': 'song000000a',
        'title': 'Kept',
        'artists': [
          {'name': 'Band'}
        ],
        'album': {'name': 'Album', 'id': 'MPRE1'},
        'duration': 200,
        'thumbnails': [
          {'url': 'https://lh3.googleusercontent.com/cover'}
        ],
        'discoverySource': 'search',
      });
      // A file on the phone Riff no longer keeps can't play from a mix.
      await _played(repo, 'device_42', times: 20);
      // Nor a song you said never to play.
      await _played(repo, 'banned0000a', times: 20);
      BanServiceSafe.setBanHook((id) => id == 'banned0000a');

      final mix = await mixes.ensureOnRepeat(now: _now);
      expect(mix.kind, MixKind.onRepeat);
      expect(mix.tracks.map((t) => t['videoId']),
          [for (var i = 0; i < 6; i++) 'song00000${i}a']);
      final kept = mix.tracks.first;
      expect(kept['title'], 'Kept');
      expect(kept['album'], {'name': 'Album', 'id': 'MPRE1'});
      expect(kept.containsKey('discoverySource'), isFalse);
      final second = mix.tracks[1];
      expect(second['title'], 'Song song000001a');
      expect(second['artists'], [
        {'name': 'Artist song000001a'}
      ]);
      expect(second['thumbnails'], [
        {'url': 'https://i.ytimg.com/vi/song000001a/hqdefault.jpg'}
      ]);
    });

    test('too few songs: none yet; made afresh the next day', () async {
      for (var i = 0; i < 4; i++) {
        await _played(repo, 'song00000${i}a', times: 3);
      }
      expect((await mixes.ensureOnRepeat(now: _now)).tracks, isEmpty);

      await _played(repo, 'song000004a', times: 3);
      // Kept for the day ...
      expect((await mixes.ensureOnRepeat(now: _now)).tracks, isEmpty);
      // ... and made again the next.
      final tomorrow =
          await mixes.ensureOnRepeat(now: _now.add(const Duration(days: 1)));
      expect(tomorrow.tracks, hasLength(5));
    });
  });

  test("Rediscover's songs have their art", () async {
    final old = DateTime.now().subtract(const Duration(days: 200));
    for (final id in ['song000000a', 'song000001a']) {
      await repo.recordTrackPlay(id, now: old);
      await repo.recordTrackPlay(id, now: old);
    }
    final recent = await Hive.openBox('LIBRP');
    await recent.add({
      'videoId': 'song000000a',
      'title': 'Kept',
      'thumbnails': [
        {'url': 'https://lh3.googleusercontent.com/cover'}
      ],
      'playedAt': 1,
    });
    final mix = await mixes.ensureRediscover();
    final byId = {for (final t in mix.tracks) t['videoId']: t};
    expect(byId['song000000a']!['thumbnails'], [
      {'url': 'https://lh3.googleusercontent.com/cover'}
    ]);
    expect(byId['song000000a']!.containsKey('playedAt'), isFalse);
    expect(byId['song000001a']!['thumbnails'], [
      {'url': 'https://i.ytimg.com/vi/song000001a/hqdefault.jpg'}
    ]);
  });
}
