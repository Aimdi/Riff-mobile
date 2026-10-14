import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/services/apple_music_links.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/podcast_links.dart';
import 'package:harmonymusic/services/podcast_service.dart';

Album _album(String title, String artist, [String id = 'MPREb_1']) => Album(
    title: title,
    browseId: id,
    artists: [
      {'name': artist}
    ],
    thumbnailUrl: '');

Artist _artist(String name, [String id = 'UCrick']) =>
    Artist(name: name, browseId: id, thumbnailUrl: '');

/// YouTube Music's search: one song, one album, one artist.
class _Music extends GetxService implements MusicServices {
  final asked = <String>[];

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    asked.add('$filter: $query');
    return switch (filter) {
      'songs' => {
          'Songs': [
            const MediaItem(
                id: 'ytsong',
                title: 'Never Gonna Give You Up',
                artist: 'Rick Astley',
                duration: Duration(seconds: 213)),
          ],
        },
      'albums' => {
          'Albums': [
            _album('Something Else', 'Someone', 'MPREb_x'),
            _album('Whenever You Need Somebody', 'Rick Astley'),
          ],
        },
      'artists' => {
          'Artists': [_artist('Rick Astley')],
        },
      _ => <String, dynamic>{},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Apple Music links', () {
    void reads(String link, AppleMusicLinkKind kind, String id) {
      final l = appleMusicLinkFrom(link);
      expect(l?.kind, kind, reason: link);
      expect(l?.id, id, reason: link);
    }

    test('songs, albums and artists, however they are written', () {
      reads(
          'https://music.apple.com/us/album/never-gonna-give-you-up/'
              '1558533900?i=1558534271',
          AppleMusicLinkKind.song,
          '1558534271');
      reads(
          'https://music.apple.com/gb/song/never-gonna-give-you-up/1558534271',
          AppleMusicLinkKind.song,
          '1558534271');
      reads(
          'https://music.apple.com/us/album/whenever-you-need-somebody/1558533900',
          AppleMusicLinkKind.album,
          '1558533900');
      reads('https://music.apple.com/us/album/1558533900',
          AppleMusicLinkKind.album, '1558533900');
      reads('https://music.apple.com/us/artist/rick-astley/669771',
          AppleMusicLinkKind.artist, '669771');
      reads('https://itunes.apple.com/us/album/x/id1558533900?i=1558534271',
          AppleMusicLinkKind.song, '1558534271');
    });

    test("playlists, podcasts and other sites aren't", () {
      for (final link in [
        'https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd4114',
        'https://podcasts.apple.com/us/podcast/the-daily/id1200361736',
        'https://music.apple.com/us/browse',
        'https://example.com/us/album/x/123',
      ]) {
        expect(appleMusicLinkFrom(link), isNull, reason: link);
      }
    });

    test("an iTunes album is music, not a podcast; an iTunes podcast is", () {
      expect(
          podcastLinkFrom('https://itunes.apple.com/us/album/x/id123'), isNull);
      expect(
          podcastLinkFrom('https://itunes.apple.com/us/podcast/x/id123')
              ?.appleId,
          '123');
    });
  });

  group('matching', () {
    test("a song as Apple describes it, to match as Spotify's are", () {
      final song = appleMusicSong({
        'wrapperType': 'track',
        'kind': 'song',
        'trackId': 1558534271,
        'trackName': 'Never Gonna Give You Up',
        'artistName': 'Rick Astley',
        'collectionName': 'Whenever You Need Somebody',
        'trackTimeMillis': 213573,
      });
      expect(song?.searchQuery, 'Never Gonna Give You Up Rick Astley');
      expect(song?.durationMs, 213573);
      expect(appleMusicSong({'wrapperType': 'collection'}), isNull);
      expect(appleMusicSong(null), isNull);
    });

    test("YouTube Music's album: the same name, a single's too", () {
      final albums = [
        _album('Greatest Hits', 'Someone Else', 'MPREb_x'),
        _album('Blinding Lights', 'The Weeknd', 'MPREb_2'),
      ];
      expect(
          matchingAlbum('Blinding Lights - Single', 'The Weeknd', albums)
              ?.browseId,
          'MPREb_2');
      expect(matchingAlbum('Thriller', 'Michael Jackson', albums), isNull);
    });

    test("YouTube Music's artist: the same name, not a near one", () {
      expect(matchingArtist('Rick Astley', [_artist('Rick Astley')])?.browseId,
          'UCrick');
      expect(matchingArtist('Rick Astley', [_artist('Rick Ross')]), isNull);
    });
  });

  group('a link, looked up and matched', () {
    late HttpServer server;
    final base = PodcastService.directoryBase;
    late _Music music;

    setUp(() async {
      music = Get.put<MusicServices>(_Music()) as _Music;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        final id = req.uri.queryParameters['id'];
        req.response.write(jsonEncode({
          'results': [
            if (id == '1')
              {
                'wrapperType': 'track',
                'trackId': 1,
                'trackName': 'Never Gonna Give You Up',
                'artistName': 'Rick Astley',
                'trackTimeMillis': 213573,
              },
            if (id == '2')
              {
                'wrapperType': 'collection',
                'collectionName': 'Whenever You Need Somebody',
                'artistName': 'Rick Astley',
              },
            if (id == '3')
              {'wrapperType': 'artist', 'artistName': 'Rick Astley'},
          ],
        }));
        await req.response.close();
      });
      PodcastService.directoryBase = 'http://127.0.0.1:${server.port}';
    });
    tearDown(() async {
      PodcastService.directoryBase = base;
      await server.close(force: true);
      Get.reset();
    });

    test('a song plays its match', () async {
      final match = await appleMusicOnYouTubeMusic(
          const AppleMusicLink(AppleMusicLinkKind.song, '1'));
      expect(match?.song?.id, 'ytsong');
      expect(music.asked, ['songs: Never Gonna Give You Up Rick Astley']);
    });

    test('an album and an artist open theirs', () async {
      final album = await appleMusicOnYouTubeMusic(
          const AppleMusicLink(AppleMusicLinkKind.album, '2'));
      expect(album?.album?.browseId, 'MPREb_1');
      final artist = await appleMusicOnYouTubeMusic(
          const AppleMusicLink(AppleMusicLinkKind.artist, '3'));
      expect(artist?.artist?.browseId, 'UCrick');
    });

    test("one Apple doesn't know is nothing", () async {
      expect(
          await appleMusicOnYouTubeMusic(
              const AppleMusicLink(AppleMusicLinkKind.song, '9')),
          isNull);
      expect(music.asked, isEmpty);
    });
  });
}
