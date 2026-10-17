import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/services/discovery/candidate_sources.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/discovery/mix_generator.dart';
import 'package:harmonymusic/services/discovery/new_releases.dart';
import 'package:harmonymusic/services/discovery/taste_model.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/nav_parser.dart';
import 'package:hive/hive.dart';

Album _release(String id, String year, {String kind = 'Single'}) => Album(
    title: 'Release $id',
    browseId: id,
    year: year,
    description: '$kind • $year',
    thumbnailUrl: '',
    artists: const []);

MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Song $id', artist: 'Artist', extras: const {});

/// Artist pages and album tracks as YouTube Music gives them; counts the
/// pages asked for.
class _FakeMusic extends MusicServices {
  final pages = <String, Map<String, dynamic>>{};
  final albums = <String, List<MediaItem>>{};
  final artistsAsked = <String>[];

  @override
  Future<Map<String, dynamic>> getArtist(String channelId) async {
    artistsAsked.add(channelId);
    return pages[channelId] ?? {};
  }

  @override
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
          {String? playlistId,
          String? albumId,
          int? limit,
          bool related = false,
          int suggestionsLimit = 0}) async =>
      {'tracks': albums[albumId] ?? const <MediaItem>[]};
}

void main() {
  group('what counts as new', () {
    test("a release's year, or the year in its subtitle", () {
      expect(releaseYear(_release('a', '2026')), 2026);
      expect(
          releaseYear(Album(
              title: 'x',
              browseId: 'x',
              description: 'EP • 2025',
              thumbnailUrl: '',
              artists: const [])),
          2025);
      expect(
          releaseYear(Album(
              title: 'x',
              browseId: 'x',
              description: 'Album',
              thumbnailUrl: '',
              artists: const [])),
          isNull);
    });

    test("this year's; early in a year, last year's too", () {
      expect(newReleaseYear(DateTime(2026, 10, 14)), 2026);
      expect(newReleaseYear(DateTime(2027, 2, 1)), 2026);
      expect(newReleaseYear(DateTime(2027, 6, 1)), 2027);
    });

    test("an artist's newest single or EP, then newest album", () {
      final page = <String, dynamic>{
        'Singles & EPs': {
          'content': [_release('s26', '2026'), _release('s25', '2025')]
        },
        'Albums': {
          'content': [
            _release('a26', '2026', kind: 'Album'),
            _release('a25', '2025', kind: 'Album'),
          ]
        },
      };
      expect(newReleasesOn(page, sinceYear: 2026).map((a) => a.browseId),
          ['s26', 'a26']);
      expect(newReleasesOn(page, sinceYear: 2027), isEmpty);
      // The shelf by its old name.
      expect(
          newReleasesOn({
            'Singles': {
              'content': [_release('s', '2026')]
            }
          }, sinceYear: 2026)
              .single
              .browseId,
          's');
      expect(newReleasesOn({}, sinceYear: 2026), isEmpty);
    });

    test("each artist's in turn", () {
      expect(
          takeInTurns([
            ['a1', 'a2'],
            ['b1'],
            ['c1', 'c2', 'c3'],
          ]),
          ['a1', 'b1', 'c1', 'a2', 'c2', 'c3']);
    });

    test('many artists: a different few each week, all in time', () {
      final ids = [for (var i = 0; i < 5; i++) 'UC$i'];
      expect(artistsThisWeek(ids, 7, max: 10), ids);
      expect(artistsThisWeek(ids, 0, max: 2), ['UC0', 'UC1']);
      expect(artistsThisWeek(ids, 1, max: 2), ['UC2', 'UC3']);
      expect(artistsThisWeek(ids, 2, max: 2), ['UC4', 'UC0']);
    });
  });

  test("an artist page's Singles & EPs shelf is read", () {
    Map<String, dynamic> item(String id, String kind, String year) => {
          'title': {
            'runs': [
              {
                'text': 'Release $id',
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': id}
                },
              }
            ]
          },
          'subtitle': {
            'runs': [
              {'text': kind},
              {'text': ' • '},
              {'text': year},
            ]
          },
        };
    final page = parseArtistContents([
      {
        'musicCarouselShelfRenderer': {
          'header': {
            'musicCarouselShelfBasicHeaderRenderer': {
              'title': {
                'runs': [
                  {'text': 'Singles & EPs'}
                ]
              }
            }
          },
          'contents': [
            {'musicTwoRowItemRenderer': item('MPREs1', 'Single', '2026')},
            {'musicTwoRowItemRenderer': item('MPREe1', 'EP', '2025')},
          ],
        }
      }
    ]);
    final singles = (page['Singles & EPs'] as Map)['content'] as List;
    expect(singles.map((a) => (a as Album).browseId), ['MPREs1', 'MPREe1']);
    expect(singles.map((a) => (a as Album).year), ['2026', '2025']);
  });

  group('Release Radar', () {
    late Directory tmp;
    late DiscoveryRepository repo;
    late _FakeMusic music;
    late MixGenerator mixes;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_release_radar_');
      Hive.init(tmp.path);
      repo = DiscoveryRepository();
      await repo.open();
      music = _FakeMusic();
      mixes = MixGenerator(
          repo: repo,
          taste: TasteModel(repo),
          sources: CandidateSources(music: music, repo: repo));
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test("new releases of the artists you follow, a track each, in turn",
        () async {
      await repo.followArtist('UCa', name: 'A');
      await repo.followArtist('UCb', name: 'B');
      music.pages['UCa'] = {
        // Top songs aren't new.
        'Songs': {
          'content': [_song('hit')]
        },
        'Singles & EPs': {
          'content': [_release('sA', '2026'), _release('oldA', '2019')]
        },
        'Albums': {
          'content': [_release('alA', '2026', kind: 'Album')]
        },
      };
      music.pages['UCb'] = {
        'Singles & EPs': {
          'content': [_release('sB', '2026')]
        },
      };
      music.albums['sA'] = [_song('a1')];
      music.albums['alA'] = [_song('a2'), _song('a3')];
      music.albums['sB'] = [_song('b1')];
      music.albums['oldA'] = [_song('old')];

      final mix = await mixes.ensureReleaseRadar(now: DateTime(2026, 10, 14));
      expect(mix.kind, MixKind.releaseRadar);
      expect(mix.tracks.map((t) => t['videoId']), ['a1', 'b1', 'a2']);
      expect(repo.getMix('release_radar')!.tracks, hasLength(3));
    });

    test('nothing new: looked for again the next day, not a week on', () async {
      await repo.followArtist('UCa', name: 'A');
      await repo.saveMix(GeneratedMix(
        id: 'release_radar',
        title: 'Release Radar',
        reason: '',
        kind: MixKind.releaseRadar,
        tracks: const [],
        generatedTs: DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
      ));
      await mixes.ensureReleaseRadar(now: DateTime(2026, 10, 14));
      expect(music.artistsAsked, ['UCa']);

      // Found nothing again, today: kept until tomorrow.
      await mixes.ensureReleaseRadar(now: DateTime(2026, 10, 14));
      expect(music.artistsAsked, ['UCa']);
    });

    test('artists in your Library from before count as followed', () async {
      final box = await Hive.openBox('LibraryArtists');
      await box.put('UCold', {'name': 'Old'});
      music.pages['UCold'] = {
        'Singles & EPs': {
          'content': [_release('s', '2026')]
        },
      };
      music.albums['s'] = [_song('x')];
      final mix = await mixes.ensureReleaseRadar(now: DateTime(2026, 10, 14));
      expect(mix.tracks.single['videoId'], 'x');
    });
  });
}
