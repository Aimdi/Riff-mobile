import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/server_login.dart';

/// A song's stream link with a token login, and a cover link with the
/// older login (the password, hex-encoded: "pass").
const _stream = 'https://music.example.com/rest/stream.view?id=7&u=me'
    '&t=0123abcd&s=salt42&v=1.16.1&c=Riff&f=json';
const _cover = 'https://music.example.com/rest/getCoverArt.view?id=al-3'
    '&size=400&u=me&p=enc%3A70617373&v=1.16.1&c=Riff&f=json';

void main() {
  test("a link to your server loses its login; others stay as they are", () {
    expect(Uri.parse(withoutServerLogin(_stream)).queryParameters,
        {'id': '7', 'v': '1.16.1', 'c': 'Riff', 'f': 'json'});
    expect(Uri.parse(withoutServerLogin(_cover)).queryParameters,
        {'id': 'al-3', 'size': '400', 'v': '1.16.1', 'c': 'Riff', 'f': 'json'});
    expect(hasServerLogin(_stream), isTrue);
    expect(hasServerLogin(_cover), isTrue);
    expect(hasServerLogin(withoutServerLogin(_stream)), isFalse);

    // Not a music server's: a podcast's ?t= and ?s=, YouTube's art.
    const episode = 'https://cdn.example.com/ep1.mp3?t=30&s=feed';
    expect(withoutServerLogin(episode), episode);
    expect(hasServerLogin(episode), isFalse);
    const art = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg?sqp=x&rs=y';
    expect(withoutServerLogin(art), art);
  });

  test('an exported playlist carries no login, and the rest as it was', () {
    final exported = withoutServerLogins({
      'playlistInfo': {'title': 'Home', 'thumbnailUrl': _cover},
      'songs': [
        {
          'videoId': 'cloud_7',
          'title': 'Home song',
          'url': _stream,
          'thumbnails': [
            {'url': _cover}
          ],
          'duration': 215,
        },
        {
          'videoId': 'dQw4w9WgXcQ',
          'title': 'Never Gonna Give You Up',
          'url': null,
          'thumbnails': [
            {'url': 'https://lh3.googleusercontent.com/x=w120-h120'}
          ],
        },
      ],
    }) as Map;
    final text = jsonEncode(exported);
    for (final secret in ['0123abcd', 'salt42', '70617373']) {
      expect(text, isNot(contains(secret)));
    }
    final songs = exported['songs'] as List;
    expect((songs.first as Map)['duration'], 215);
    expect(songs.last, {
      'videoId': 'dQw4w9WgXcQ',
      'title': 'Never Gonna Give You Up',
      'url': null,
      'thumbnails': [
        {'url': 'https://lh3.googleusercontent.com/x=w120-h120'}
      ],
    });
  });

  test('imported back, its links are signed with the login Riff has now', () {
    const server = 'https://music.example.com';
    const login = {
      'u': 'me',
      't': 'fresh',
      's': 'newsalt',
      'v': '1.16.1',
      'c': 'Riff',
      'f': 'json',
    };
    final bare = withoutServerLogin(_stream);
    expect(
        Uri.parse(signedServerUrl(bare, server: server, login: login))
            .queryParameters,
        {'id': '7', ...login});
    // Another server's link, one signed already, or no login to sign with.
    expect(
        signedServerUrl(bare,
            server: 'https://other.example.org', login: login),
        bare);
    expect(signedServerUrl(_stream, server: server, login: login), _stream);
    expect(signedServerUrl(bare, server: server, login: const {}), bare);

    final imported = withServerLogins({
      'songs': [
        {
          'url': bare,
          'thumbnails': [
            {'url': withoutServerLogin(_cover)}
          ],
        }
      ],
    }, server: server, login: login) as Map;
    final song = (imported['songs'] as List).single as Map;
    expect(hasServerLogin(song['url'] as String), isTrue);
    expect(
        hasServerLogin(
            ((song['thumbnails'] as List).single as Map)['url'] as String),
        isTrue);
  });
}
