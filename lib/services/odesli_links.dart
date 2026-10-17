/// Links from other music apps (Tidal, Deezer, Amazon Music, SoundCloud,
/// Pandora, …) and song.link's own pages, opened in Riff through Odesli
/// (song.link), which knows each song's and album's link on YouTube Music.
/// Spotify's and Apple Music's songs and albums go through it first too:
/// its match is exact where Riff's own is a best guess.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '/utils/helper.dart';

/// Odesli's public API (no key needed, ten calls a minute).
const odesliApi = 'https://api.song.link/v1-alpha.1/links';

const _serviceHosts = [
  'tidal.com',
  'deezer.com',
  'deezer.page.link',
  'dzr.page.link',
  'soundcloud.com',
  'pandora.com',
  'pandora.app.link',
  'napster.com',
  'audiomack.com',
  'anghami.com',
  'boomplay.com',
  'song.link',
  'album.link',
  'odesli.co',
];

/// Whether [link] is another music app's (or song.link's) page, which
/// Odesli maps to YouTube Music.
bool isMusicServiceLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host.startsWith('music.amazon.') || host.startsWith('music.yandex.')) {
    return true;
  }
  return _serviceHosts.any((h) => host == h || host.endsWith('.$h'));
}

/// A song.link page for a YouTube video (song.link/y/<id>): its link,
/// without asking Odesli.
String? youtubeLinkInSongLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || !const {'song.link', 'album.link'}.contains(uri.host)) {
    return null;
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final at = segments.indexOf('y');
  if (at < 0 || at + 1 >= segments.length) return null;
  final id = segments[at + 1];
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
      ? 'https://music.youtube.com/watch?v=$id'
      : null;
}

/// The YouTube Music link (else YouTube's) in Odesli's answer [json], or
/// null when it has none.
String? youtubeLinkFromOdesli(Object? json) {
  final links = json is Map ? json['linksByPlatform'] : null;
  if (links is! Map) return null;
  for (final platform in const ['youtubeMusic', 'youtube']) {
    final entry = links[platform];
    final url = entry is Map ? '${entry['url'] ?? ''}' : '';
    if (url.startsWith('https://')) return url;
  }
  return null;
}

/// [link]'s page on YouTube Music (else YouTube), as Odesli knows it; null
/// when it doesn't, or can't be reached.
Future<String?> youtubeLinkViaOdesli(String link, {Dio? dio}) async {
  final local = youtubeLinkInSongLink(link);
  if (local != null) return local;
  try {
    final res = await (dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )))
        .get<String>(odesliApi,
            queryParameters: {'url': link.trim()},
            options: Options(
                responseType: ResponseType.plain, validateStatus: (_) => true));
    if (res.statusCode != 200) return null;
    return youtubeLinkFromOdesli(jsonDecode(res.data ?? ''));
  } catch (e) {
    printERROR('Odesli failed ($link): $e');
    return null;
  }
}
