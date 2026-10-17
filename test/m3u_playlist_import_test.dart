import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/csv_playlist_import.dart';
import 'package:harmonymusic/services/m3u_playlist_import.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  /// The tracks each video's watch queue starts with.
  final songs = <String, List<MediaItem>>{};
  final looked = <String>[];

  /// What a search finds.
  List<MediaItem> found = const [];
  int searches = 0;

  @override
  Future<List> getSongWithId(String songId) async {
    looked.add(songId);
    final tracks = songs[songId];
    return tracks == null ? [false, null] : [true, tracks];
  }

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    searches++;
    return {'Songs': found};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Title, artist and length (ms) of each track read.
List<(String, String, int?)> _read(CsvPlaylist p) =>
    [for (final t in p.tracks) (t.title, t.artists, t.durationMs)];

void main() {
  test(
      'a player\'s M3U: #EXTINF says artist, title and length; #PLAYLIST '
      'its name', () {
    const m3u = '#EXTM3U\r\n'
        '#PLAYLIST:Road trip\r\n'
        '#EXTINF:354,Queen - Bohemian Rhapsody\r\n'
        'D:\\Music\\Queen\\A Night at the Opera\\11 Bohemian Rhapsody.flac\r\n'
        '\r\n'
        '#EXTINF:-1,Daft Punk - One More Time\r\n'
        'file:///home/me/Music/Daft%20Punk/Discovery/01%20One%20More%20Time.mp3\r\n';
    final p = parsePlaylistM3u(m3u);
    expect(p.format, CsvPlaylistFormat.m3u);
    expect(p.name, 'Road trip');
    expect(_read(p), [
      ('Bohemian Rhapsody', 'Queen', 354000),
      ('One More Time', 'Daft Punk', null),
    ]);
    expect(p.skipped, 0);
  });

  test('iTunes writes "Title - Artist": the file or its folder tells', () {
    const m3u = '#EXTM3U\n'
        '#EXTINF:354,Bohemian Rhapsody - Queen\n'
        '/Users/me/Music/iTunes/iTunes Media/Music/Queen/A Night at the Opera/'
        '11 Bohemian Rhapsody.m4a\n'
        // A compilation: the file's own name says which is the title.
        '#EXTINF:200,Song Two - Remastered - Some Artist\n'
        '/Users/me/Music/iTunes/iTunes Media/Music/Compilations/Hits/'
        '1-03 Song Two - Remastered.m4a\n'
        // A dash in the title, written artist first.
        '#EXTINF:200,Queen - Bohemian Rhapsody - Remastered 2011\n'
        'Queen/Greatest Hits/01 Bohemian Rhapsody - Remastered 2011.mp3\n';
    expect(_read(parsePlaylistM3u(m3u)), [
      ('Bohemian Rhapsody', 'Queen', 354000),
      ('Song Two - Remastered', 'Some Artist', 200000),
      ('Bohemian Rhapsody - Remastered 2011', 'Queen', 200000),
    ]);
  });

  test(
      'plain paths: titles from file names without track numbers, artists '
      'from folders but not the phone\'s own', () {
    const m3u = '/storage/emulated/0/Music/Queen/Greatest Hits/'
        '01 - Bohemian Rhapsody.mp3\n'
        '/storage/emulated/0/Music/Daft Punk/One More Time.mp3\n'
        '/storage/emulated/0/Download/Daft Punk - Digital Love.mp3\n'
        '/storage/emulated/0/Download/12 Song Without Artist.mp3\n'
        '/storage/emulated/0/Music/50 Cent - In Da Club.mp3\n';
    expect(_read(parsePlaylistFile('phone.m3u', m3u)), [
      ('Bohemian Rhapsody', 'Queen', null),
      ('One More Time', 'Daft Punk', null),
      ('Digital Love', 'Daft Punk', null),
      ('Song Without Artist', '', null),
      ('In Da Club', '50 Cent', null),
    ]);
  });

  test('#EXTART, attributes with commas; streams without a title skipped', () {
    const m3u = '#EXTM3U\n'
        '#EXTINF:215 tvg-name="Hits, vol. 1" group-title="x",'
        'Daft Punk - Around the World\n'
        '#EXTART:Daft Punk\n'
        'https://example.com/stream/7.mp3\n'
        '#EXTINF:-1,\n'
        'http://radio.example.com:8000/live\n'
        '#EXTVLCOPT:network-caching=1000\n'
        'C:\\Music\\Unknown Artist\\Unknown Album\\Track 3.wav\n';
    final p = parsePlaylistM3u(m3u);
    expect(_read(p), [
      ('Around the World', 'Daft Punk', 215000),
      ('Track 3', '', null),
    ]);
    expect(p.skipped, 1);
  });

  test('YouTube links name the track; without a title the link stands in', () {
    const m3u = '#EXTM3U\n'
        '#EXTINF:213,Rick Astley - Never Gonna Give You Up\n'
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ&si=abc\n'
        'https://youtu.be/kJQP7kiw5Fk\n'
        'https://www.youtube.com/playlist?list=PL123\n';
    final p = parsePlaylistM3u(m3u);
    expect(p.tracks.map((t) => (t.title, t.artists, t.youtubeId)), [
      ('Never Gonna Give You Up', 'Rick Astley', 'dQw4w9WgXcQ'),
      ('https://youtu.be/kJQP7kiw5Fk', '', 'kJQP7kiw5Fk'),
    ]);
    expect(p.skipped, 1);
    // No stored match is kept for entries of a file.
    expect(p.tracks.map((t) => t.id), ['csv_1', 'csv_2']);
  });

  test('PLS: its entries in their numbers\' order', () {
    const pls = '[playlist]\n'
        'NumberOfEntries=3\n'
        'File2=/music/Queen/Greatest Hits/02 Another One Bites the Dust.mp3\n'
        'Title2=Queen - Another One Bites the Dust\n'
        'Length2=215\n'
        'File1=https://youtu.be/dQw4w9WgXcQ\n'
        'Title1=Rick Astley - Never Gonna Give You Up\n'
        'Length1=-1\n'
        'File3=http://radio.example.com/live\n'
        'Version=2\n';
    final p = parsePlaylistPls(pls);
    expect(p.format, CsvPlaylistFormat.pls);
    expect(
        p.tracks.map((t) => (t.title, t.artists, t.durationMs, t.youtubeId)), [
      ('Never Gonna Give You Up', 'Rick Astley', null, 'dQw4w9WgXcQ'),
      ('Another One Bites the Dust', 'Queen', 215000, null),
    ]);
    expect(p.skipped, 1);
  });

  test('a file read for what it is: by its name, else its first line', () {
    expect(
        parsePlaylistFile('mix.M3U8', 'a.mp3').format, CsvPlaylistFormat.m3u);
    expect(parsePlaylistFile('mix.txt', '\uFEFF#EXTM3U\na.mp3').format,
        CsvPlaylistFormat.m3u);
    expect(parsePlaylistFile('mix.pls', 'File1=a.mp3').format,
        CsvPlaylistFormat.pls);
    expect(parsePlaylistFile('mix', '[playlist]\nFile1=a.mp3').format,
        CsvPlaylistFormat.pls);
    expect(parsePlaylistFile('mix.csv', 'Title,Artist\nA,B').format,
        CsvPlaylistFormat.generic);
    expect(() => parsePlaylistFile('notes.txt', 'just words'),
        throwsA(isA<FormatException>()));
  });

  test('UTF-8, or Latin-1 when a file isn\'t', () {
    expect(
        decodePlaylistBytes(utf8.encode('Beyoncé - Halo')), 'Beyoncé - Halo');
    expect(
        decodePlaylistBytes(latin1.encode('Beyoncé - Halo')), 'Beyoncé - Halo');
  });

  group('a linked track', () {
    late Directory tmp;
    late _FakeMusic music;
    late SpotifyImportService svc;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_m3u_');
      Hive.init(tmp.path);
      music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
      svc = SpotifyImportService()..deezer = null;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('is taken as it is, before any search', () async {
      music.songs['dQw4w9WgXcQ'] = const [
        MediaItem(id: 'other00000a', title: 'Up next'),
        MediaItem(id: 'dQw4w9WgXcQ', title: 'Never Gonna Give You Up'),
      ];
      final item = await svc.resolveTrack(const SpotifyTrackRef(
          id: 'csv_1',
          title: 'https://youtu.be/dQw4w9WgXcQ',
          artists: '',
          youtubeId: 'dQw4w9WgXcQ'));
      expect(item?.id, 'dQw4w9WgXcQ');
      expect(music.searches, 0);
    });

    test("one that's no song is looked for by its title", () async {
      music.found = const [
        MediaItem(
            id: 'found00000a',
            title: 'Never Gonna Give You Up',
            artist: 'Rick Astley'),
      ];
      final item = await svc.resolveTrack(const SpotifyTrackRef(
          id: 'csv_1',
          title: 'Never Gonna Give You Up',
          artists: 'Rick Astley',
          youtubeId: 'notASong00a'));
      expect(music.looked, ['notASong00a']);
      expect(item?.id, 'found00000a');
    });
  });
}
