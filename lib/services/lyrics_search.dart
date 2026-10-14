/// Search lyrics, as Metrolist and InnerTune let you: when the lyrics found
/// for a song are wrong (another version, a cover) or there are none, look
/// them up on LRCLIB by any words and pick the right ones. They're kept for
/// that song from then on.
library;

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '/services/ban_service.dart' show splitArtistCredit;
import '/services/synced_lyrics_service.dart';

/// LRCLIB's search, by any words (`q`).
const String lrclibSearchUrl = 'https://lrclib.net/api/search';

/// One of LRCLIB's lyrics for a search.
class LyricsCandidate {
  const LyricsCandidate({
    required this.track,
    required this.artist,
    this.album,
    this.durationSec,
    this.synced,
    this.plain,
  });

  final String track;
  final String artist;
  final String? album;
  final int? durationSec;
  final String? synced;
  final String? plain;

  bool get isSynced => synced != null && synced!.isNotEmpty;

  /// What the lyrics cache keeps for a song, as the lookup keeps what it
  /// finds ([SyncedLyricsService.getSyncedLyrics]); [chosen] marks it picked.
  Map<String, dynamic> get cacheEntry => {
        'synced': synced ?? '',
        'plainLyrics': plain ?? '',
        'source': 'lrclib',
        'chosen': true,
      };

  /// From an LRCLIB result; null for an instrumental or one without lyrics.
  static LyricsCandidate? fromLrclib(Object? result) {
    if (result is! Map || result['instrumental'] == true) return null;
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    final track = text(result['trackName']) ?? text(result['name']);
    final synced = text(result['syncedLyrics']);
    final plain = text(result['plainLyrics']);
    if (track == null || (synced == null && plain == null)) return null;
    final duration = result['duration'];
    return LyricsCandidate(
      track: track.trim(),
      artist: text(result['artistName'])?.trim() ?? '',
      album: text(result['albumName'])?.trim(),
      durationSec: duration is num ? duration.round() : null,
      synced: synced,
      plain: plain,
    );
  }
}

/// LRCLIB's answer to a search as lyrics to pick from, best first for a
/// song [durationSec] long: synced ones first, then the nearest in length;
/// otherwise in LRCLIB's order.
List<LyricsCandidate> lyricsCandidates(Object? response, int? durationSec) {
  if (response is! List) return const [];
  final found = [
    for (final r in response)
      if (LyricsCandidate.fromLrclib(r) case final c?) c
  ];
  int off(LyricsCandidate c) => durationSec == null || c.durationSec == null
      ? 1 << 30
      : (c.durationSec! - durationSec).abs();
  final order = {for (var i = 0; i < found.length; i++) found[i]: i};
  return found
    ..sort((a, b) {
      if (a.isSynced != b.isSynced) return a.isSynced ? -1 : 1;
      final byLength = off(a).compareTo(off(b));
      return byLength != 0 ? byLength : order[a]!.compareTo(order[b]!);
    });
}

/// "(feat. …)", "[Official Video]", "(Remastered 2011)" and the like.
final _titleNoise = RegExp(
    r'\s*[\(\[][^\)\]]*\b(feat|ft|official|video|audio|lyrics?|'
    r'visuali[sz]er|remaster(ed)?)\b[^\)\]]*[\)\]]',
    caseSensitive: false);

/// " - Remastered 2011", " - 2009 Remaster".
final _remasterTail =
    RegExp(r'\s+-\s+[^-]*\bremaster(ed)?\b.*$', caseSensitive: false);

/// What to search for [song]'s lyrics: its title without what lyrics sites
/// leave out ("(feat. …)", "[Official Video]", " - Remastered"), and its
/// first artist.
String lyricsSearchQuery(MediaItem song) {
  final title = song.title
      .replaceAll(_titleNoise, '')
      .replaceAll(_remasterTail, '')
      .trim();
  final artists = splitArtistCredit(song.artist ?? '');
  return [title, if (artists.isNotEmpty) artists.first].join(' ').trim();
}

class LyricsSearch {
  LyricsSearch._();

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// LRCLIB's search for [query] (its JSON).
  @visibleForTesting
  static Future<Object?> Function(String query) fetch = (query) async =>
      (await _dio.get(lrclibSearchUrl, queryParameters: {'q': query})).data;

  /// Lyrics for [query], best first for [song].
  static Future<List<LyricsCandidate>> search(
          String query, MediaItem song) async =>
      lyricsCandidates(await fetch(query), song.duration?.inSeconds);

  /// [picked] are [song]'s lyrics from now on.
  static Future<void> choose(MediaItem song, LyricsCandidate picked) =>
      SyncedLyricsService.keep(song.id, picked.cacheEntry);
}
