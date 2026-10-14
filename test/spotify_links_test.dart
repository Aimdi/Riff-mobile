import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_links.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:harmonymusic/services/spotify_links.dart';

/// Answers requests from a script, recording what was asked.
class _Scripted implements HttpClientAdapter {
  _Scripted(this.handler);
  final ResponseBody Function(RequestOptions o) handler;
  final asked = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    asked.add(o.uri);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

const _id = '4cOdK2wGLETKBW3PvgPWqT';

void main() {
  group('Spotify links', () {
    test('tracks, albums and playlists, however they are written', () {
      SpotifyLink? read(String link) => spotifyLinkFrom(link);
      expect(read('https://open.spotify.com/track/$_id?si=abc')?.kind,
          SpotifyLinkKind.track);
      expect(read('https://open.spotify.com/intl-de/album/$_id')?.kind,
          SpotifyLinkKind.album);
      expect(
          read('https://open.spotify.com/intl-pt-br/playlist/$_id')?.id, _id);
      expect(read('https://play.spotify.com/track/$_id')?.kind,
          SpotifyLinkKind.track);
      expect(read('https://open.spotify.com/embed/playlist/$_id')?.kind,
          SpotifyLinkKind.playlist);
      expect(read('spotify:track:$_id')?.url,
          'https://open.spotify.com/track/$_id');
    });

    test('anything else is none', () {
      for (final link in [
        'https://open.spotify.com/artist/$_id',
        'https://open.spotify.com/episode/$_id',
        'https://open.spotify.com/track/short',
        'https://example.com/track/$_id',
        'spotify:artist:$_id',
        'https://music.youtube.com/watch?v=abc',
      ]) {
        expect(spotifyLinkFrom(link), isNull, reason: link);
      }
    });

    test('a spotify: URI in shared text is found as a link', () {
      expect(linkInText('Play this spotify:track:$_id'), 'spotify:track:$_id');
      expect(isSpotifyShortLink('https://spotify.link/AbCdEf'), isTrue);
      expect(
          isSpotifyShortLink('https://open.spotify.com/track/$_id'), isFalse);
    });
  });

  group("a Spotify short link", () {
    test('followed to where it leads', () async {
      final adapter = _Scripted((o) => ResponseBody.fromString('', 200)
        ..redirects = [
          RedirectRecord(
              302, 'GET', Uri.parse('https://open.spotify.com/track/$_id'))
        ]);
      final link = await followSpotifyShortLink('https://spotify.link/AbCdEf',
          dio: Dio()..httpClientAdapter = adapter);
      expect(link?.kind, SpotifyLinkKind.track);
      expect(link?.id, _id);
    });

    test("or to the link in the page it sends you to; none if it hasn't one",
        () async {
      var page = '<a href="https://open.spotify.com/album/$_id?si=1">Open</a>';
      final adapter = _Scripted((o) => ResponseBody.fromString(page, 200));
      final dio = Dio()..httpClientAdapter = adapter;
      expect(
          (await followSpotifyShortLink('https://spotify.link/x', dio: dio))
              ?.kind,
          SpotifyLinkKind.album);
      page = '<html>Nothing here</html>';
      expect(await followSpotifyShortLink('https://spotify.link/x', dio: dio),
          isNull);
    });
  });

  group("a track as Spotify's embed page describes it", () {
    test('its name, artists and length', () {
      final track = spotifyEmbedTrack({
        'type': 'track',
        'name': 'Never Gonna Give You Up',
        'artists': [
          {'name': 'Rick Astley', 'uri': 'spotify:artist:x'},
        ],
        'duration': 213573,
      }, id: _id);
      expect(track?.title, 'Never Gonna Give You Up');
      expect(track?.artists, 'Rick Astley');
      expect(track?.durationMs, 213573);
      expect(track?.id, _id);
      expect(track?.searchQuery, 'Never Gonna Give You Up Rick Astley');
    });

    test('or its title and the line under it', () {
      final track = spotifyEmbedTrack({
        'title': 'Song',
        'subtitle': 'Artist A, Artist B',
        'duration': {'totalMilliseconds': 1000},
      }, id: _id);
      expect(track?.artists, 'Artist A, Artist B');
      expect(track?.durationMs, 1000);
    });

    test('nothing that names no track', () {
      expect(spotifyEmbedTrack(null, id: _id), isNull);
      expect(spotifyEmbedTrack({'name': ''}, id: _id), isNull);
    });
  });

  test("Spotify's Web API gives a track's ISRC", () async {
    final adapter = _Scripted((o) => ResponseBody.fromString(
        jsonEncode({
          'id': _id,
          'type': 'track',
          'name': 'Never Gonna Give You Up',
          'artists': [
            {'name': 'Rick Astley'}
          ],
          'duration_ms': 213573,
          'external_ids': {'isrc': 'gbarl9300135'},
          'album': {
            'name': 'Whenever You Need Somebody',
            'images': [
              {'url': 'https://i.scdn.co/image/x'}
            ],
          },
        }),
        200));
    final api = SpotifyApiService(
      auth: SpotifyAuthService(),
      dio: Dio()..httpClientAdapter = adapter,
      token: () async => 't',
      refresh: () async => true,
      sleep: (_) async {},
      useCache: false,
    );
    final track = await api.fetchTrack(_id);
    expect(adapter.asked.single.path, '/v1/tracks/$_id');
    expect(track?.title, 'Never Gonna Give You Up');
    expect(track?.isrc, 'GBARL9300135');
    expect(track?.album, 'Whenever You Need Somebody');
  });
}
