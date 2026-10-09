import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/candidate_sources.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:hive/hive.dart';

/// Counts the YouTube calls a related-tracks lookup makes; radio answers
/// with [radio] after [gate] opens, Related has nothing.
class _FakeMusic extends MusicServices {
  int radioCalls = 0;
  int relatedCalls = 0;
  List<MediaItem> radio = const [];
  Completer<void> gate = Completer<void>()..complete();

  @override
  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    radioCalls++;
    await gate.future;
    return {'tracks': this.radio};
  }

  @override
  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    relatedCalls++;
    return <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> search(String query,
          {String? filter,
          String? scope,
          int limit = 30,
          bool ignoreSpelling = false,
          String? filterParams}) async =>
      {};
}

MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Song $id', artist: 'Artist', extras: const {});

void main() {
  late Directory tmp;
  late _FakeMusic music;
  late CandidateSources sources;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_candidates_');
    Hive.init(tmp.path);
    final repo = DiscoveryRepository();
    await repo.open();
    music = _FakeMusic();
    sources = CandidateSources(music: music, repo: repo);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('a video seed fetches its radio once, without duplicates', () async {
    music.radio = [_song('r1'), _song('r2'), _song('r3')];
    const seed = MediaItem(
        id: 'vid',
        title: 'Clip',
        extras: {'videoType': 'MUSIC_VIDEO_TYPE_OMV'});
    final related = await sources.relatedTracks('vid', seed: seed);
    // Fewer than 10 tracks used to trigger the same radio request again
    // and append r1..r3 a second time.
    expect(music.radioCalls, 1);
    expect(related.map((m) => m['videoId']), ['r1', 'r2', 'r3']);
  });

  test('a song seed still falls back to its radio', () async {
    music.radio = [_song('r1')];
    final related = await sources.relatedTracks('song', seed: _song('song'));
    expect(music.relatedCalls, 1);
    expect(music.radioCalls, 1);
    expect(related.map((m) => m['videoId']), ['r1']);
  });

  test('concurrent lookups for one seed share a single fetch', () async {
    music.radio = [_song('r1'), _song('r2')];
    music.gate = Completer<void>();
    final a = sources.relatedTracks('s', seed: _song('s'));
    final b = sources.relatedTracks('s', limit: 1, seed: _song('s'));
    await Future<void>.delayed(Duration.zero);
    music.gate.complete();
    final results = await Future.wait([a, b]);
    expect(music.relatedCalls, 1);
    expect(music.radioCalls, 1);
    expect(results[0].map((m) => m['videoId']), ['r1', 'r2']);
    expect(results[1].map((m) => m['videoId']), ['r1']);
  });
}
