import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/android_auto_paging.dart';
import 'package:harmonymusic/services/ban_service.dart';
import 'package:harmonymusic/services/csv_playlist_import.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:hive/hive.dart';

void main() {
  group('Android Auto paging', () {
    test('a requested page, capped at the max page size', () {
      expect(planAutoBrowse(500, {autoPageKey: 2, autoPageSizeKey: 50}),
          const AutoRange(100, 150));
      expect(planAutoBrowse(500, {autoPageKey: 0, autoPageSizeKey: 1000}),
          const AutoRange(0, autoMaxPageSize));
      // Past the end: empty.
      expect(planAutoBrowse(30, {autoPageKey: 5, autoPageSizeKey: 20}),
          const AutoRange(30, 30));
      // Strings and doubles from the platform bundle still work.
      expect(planAutoBrowse(300, {autoPageKey: '1', autoPageSizeKey: 20.0}),
          const AutoRange(20, 40));
    });

    test('no paging asked: short lists whole, long ones as sections', () {
      expect(planAutoBrowse(120, null), const AutoRange(0, 120));
      final plan = planAutoBrowse(250, const {});
      expect(plan, isA<AutoSections>());
      expect((plan as AutoSections).starts, [0, 100, 200]);
      expect(autoSectionLabel(200, 250), '201–250');
      expect(autoSectionLabel(0, 250), '1–100');
    });

    test('bad paging extras fall back to the unpaged rules', () {
      expect(planAutoBrowse(50, {autoPageKey: -1, autoPageSizeKey: 10}),
          const AutoRange(0, 50));
      expect(planAutoBrowse(50, {autoPageKey: 0, autoPageSizeKey: 0}),
          const AutoRange(0, 50));
    });

    test('section ids round trip, parent ids with colons too', () {
      final id = autoSectionId('aa_pod_feed:https://x/feed', 200);
      final back = parseAutoSectionId(id)!;
      expect(back.parentId, 'aa_pod_feed:https://x/feed');
      expect(back.start, 200);
      expect(parseAutoSectionId('LIBFAV'), isNull);
      expect(parseAutoSectionId('aa_section:x:LIBFAV'), isNull);
      expect(parseAutoSectionId('aa_section:5:'), isNull);
    });

    test('extras slimmed: long text cut, nested data dropped', () {
      final out = slimAutoExtras({
        'description': 'x' * 5000,
        'libraryId': 'LIBFAV',
        'isPodcast': true,
        'length': 3,
        'artists': [
          {'name': 'A'}
        ],
        'album': {'id': 'MPRE'},
      });
      expect((out['description'] as String).length, autoTextMax + 1);
      expect(out['libraryId'], 'LIBFAV');
      expect(out['isPodcast'], isTrue);
      expect(out.containsKey('artists'), isFalse);
      expect(out.containsKey('album'), isFalse);
      expect(slimAutoExtras(null), isEmpty);
    });
  });

  group('blacklist rules', () {
    bool none(String _) => false;

    test('song, any artist, or album blocks a track', () {
      bool blocked({String? id, List<String> artists = const [], String? album,
              Set<String> songs = const {}, Set<String> arts = const {},
              Set<String> cols = const {}}) =>
          trackBlocked(
            videoId: id,
            artistNames: artists,
            albumId: album,
            songBanned: songs.contains,
            artistBanned: arts.contains,
            collectionBanned: cols.contains,
          );
      expect(blocked(id: 'v1', songs: {'v1'}), isTrue);
      expect(blocked(id: 'v1', artists: ['A', 'B'], arts: {'B'}), isTrue);
      expect(blocked(id: 'v1', album: 'MPRE1', cols: {'MPRE1'}), isTrue);
      expect(blocked(id: 'v1', artists: ['A'], album: 'MPRE2'), isFalse);
      expect(
          trackBlocked(
              videoId: null,
              artistNames: const [],
              songBanned: none,
              artistBanned: none,
              collectionBanned: none),
          isFalse);
    });

    test('artists and album read from YouTube track maps', () {
      expect(
          trackArtistNames({
            'artists': [
              {'name': 'A'},
              {'name': ' '},
              'B'
            ]
          }),
          ['A', 'B']);
      expect(trackArtistNames({'artist': 'Solo'}), ['Solo']);
      expect(trackArtistNames({}), isEmpty);
      expect(trackAlbumId({'album': {'id': 'MPRE1', 'name': 'X'}}), 'MPRE1');
      expect(trackAlbumId({'albumId': 'MPRE2'}), 'MPRE2');
      expect(trackAlbumId({'album': 'name only'}), isNull);
    });

    test('credits split into single artists', () {
      expect(splitArtistCredit('A, B & C feat. D'), ['A', 'B', 'C', 'D']);
      expect(splitArtistCredit('Simon & Garfunkel'), ['Simon', 'Garfunkel']);
      expect(splitArtistCredit('X ft. Y'), ['X', 'Y']);
      expect(splitArtistCredit('Featherweight'), ['Featherweight']);
    });
  });

  group('blacklist store (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_bans_');
      Hive.init(tmp.path);
      for (final b in ['BannedSongs', 'BannedArtists', 'BannedCollections']) {
        await Hive.openBox(b);
      }
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('filterTracks drops banned songs, artists and albums', () async {
      await BanService.banRaw('s1', 'Song', 'Someone');
      await BanService.banArtist('Bad Artist');
      await BanService.banCollection('MPREbad', 'Bad Album', 'album');
      final tracks = [
        {'videoId': 's1'},
        {
          'videoId': 's2',
          'artists': [
            {'name': 'Good'},
            {'name': 'Bad Artist'}
          ]
        },
        {'videoId': 's3', 'album': {'id': 'MPREbad'}},
        {'videoId': 's4', 'artists': [{'name': 'Good'}]},
      ];
      expect(BanService.filterTracks(tracks).map((t) => t['videoId']), ['s4']);
      // The song asked for explicitly stays.
      expect(
          BanService.filterTracks(tracks, keepVideoId: 's1')
              .map((t) => t['videoId']),
          ['s1', 's4']);
    });

    test('artist bans match inside credits; old whole-credit bans too',
        () async {
      await BanService.banArtist('B');
      expect(BanService.isArtistBanned('A, B & C'), isTrue);
      expect(BanService.isArtistBanned('A & C'), isFalse);
      await BanService.banArtist('X, Y'); // stored by older versions
      expect(BanService.isArtistBanned('X, Y'), isTrue);
    });

    test('MediaItem check and the primary artist to ban', () async {
      await BanService.banCollection('MPRE1', 'Album', 'album');
      const song = MediaItem(
          id: 'v9',
          title: 'T',
          artist: 'Lead, Guest',
          extras: {
            'album': {'id': 'MPRE1', 'name': 'Album'}
          });
      expect(BanService.isMediaItemBlocked(song), isTrue);
      expect(BanService.primaryArtist(song), 'Lead');
      expect(
          BanService.primaryArtist(const MediaItem(
              id: 'v', title: 't', extras: {
            'artists': [
              {'name': 'First'},
              {'name': 'Second'}
            ]
          })),
          'First');
      expect(BanService.primaryArtist(const MediaItem(id: 'v', title: 't')),
          isNull);
    });
  });

  group('CSV import', () {
    test('quotes, doubled quotes, commas and line breaks inside fields', () {
      final rows = parseCsv('﻿a,b,c\r\n"x, y","say ""hi""","line\nbreak"\r\n');
      expect(rows, [
        ['a', 'b', 'c'],
        ['x, y', 'say "hi"', 'line\nbreak'],
      ]);
    });

    test('semicolon and tab files', () {
      expect(parseCsv('a;b\n1;2'), [
        ['a', 'b'],
        ['1', '2']
      ]);
      expect(parseCsv('a\tb\n1\t2'), [
        ['a', 'b'],
        ['1', '2']
      ]);
    });

    test('Exportify: header names, ISRC, duration, artists', () {
      const csv = 'Track URI,Track Name,Artist Name(s),Album Name,'
          'Duration (ms),ISRC\n'
          'spotify:track:1,Song One,"Artist A, Artist B",Album,215000,usum71900001\n'
          'spotify:track:2,Song Two,Solo;Guest,Album,0,BADISRC\n'
          'spotify:track:3,,Nobody,Album,1000,\n';
      final p = parsePlaylistCsv(csv);
      expect(p.format, CsvPlaylistFormat.exportify);
      expect(p.skipped, 1);
      expect(p.tracks, hasLength(2));
      final a = p.tracks[0];
      expect(a.id, 'spotify:track:1');
      expect(a.title, 'Song One');
      expect(a.artists, 'Artist A, Artist B');
      expect(a.durationMs, 215000);
      expect(a.isrc, 'USUM71900001');
      final b = p.tracks[1];
      expect(b.artists, 'Solo, Guest');
      expect(b.durationMs, isNull);
      expect(b.isrc, isNull);
    });

    test('TuneMyMusic: any case, playlist name', () {
      const csv = 'Track name,ARTIST NAME,Album,Playlist name,Type,ISRC\n'
          'Hey,Someone,Alb,Road Trip,Playlist,GB-ABC-12-34567\n';
      final p = parsePlaylistCsv(csv);
      expect(p.format, CsvPlaylistFormat.tuneMyMusic);
      expect(p.name, 'Road Trip');
      expect(p.tracks.single.title, 'Hey');
      expect(p.tracks.single.artists, 'Someone');
      expect(p.tracks.single.isrc, 'GBABC1234567');
    });

    test('generic title / artist CSV, and files without a title column', () {
      final p = parsePlaylistCsv('Title,Artist\nA,B\n');
      expect(p.format, CsvPlaylistFormat.generic);
      expect(p.tracks.single.searchQuery, 'A B');
      expect(() => parsePlaylistCsv('foo,bar\n1,2\n'),
          throwsA(isA<FormatException>()));
      expect(() => parsePlaylistCsv(''), throwsA(isA<FormatException>()));
    });

    test('ISRC shape', () {
      expect(isValidIsrc('USUM71900001'), isTrue);
      expect(isValidIsrc('USUM7190000'), isFalse);
      expect(isValidIsrc('12UM71900001'), isFalse);
    });

    test('summary lists what did not match', () {
      const tracks = [
        SpotifyTrackRef(id: '1', title: 'A', artists: 'X'),
        SpotifyTrackRef(id: '2', title: 'B', artists: ''),
        SpotifyTrackRef(id: '3', title: 'C', artists: 'Z'),
      ];
      final s = summarizeImport(tracks, ['ok', null, 'ok']);
      expect(s.matched, 2);
      expect(s.total, 3);
      expect(s.unmatched, ['B']);
      final s2 = summarizeImport(tracks, const <String?>[null]);
      expect(s2.unmatched, ['A — X', 'B', 'C — Z']);
    });
  });
}
