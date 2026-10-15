/// Library search matching, shared by the Songs, Playlists, Albums and
/// Artists tabs: like Spotify's and YouTube Music's library filter, every
/// word typed has to appear somewhere in the item (title, artist, album …),
/// ignoring case and accents.
library;

import 'package:audio_service/audio_service.dart';

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'č': 'c',
  'ć': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ř': 'r',
  'ł': 'l',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
};

/// Lower case without accents: "Beyoncé" → "beyonce".
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_accents[ch] ?? ch);
  }
  return out.toString();
}

/// True when every word of [query] appears in one of [fields].
bool libraryMatches(String query, Iterable<String?> fields) {
  final words = foldForSearch(query)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  // A separator no one types, so a word can't match across two fields.
  final haystack = fields.whereType<String>().map(foldForSearch).join('\u0000');
  return words.every(haystack.contains);
}

/// The text a library song is found by: title, artist and album.
List<String?> songSearchFields(MediaItem song) {
  final album = song.extras?['album'];
  return [
    song.title,
    song.artist,
    song.album,
    if (album is Map) album['name']?.toString(),
  ];
}

/// The songs of [songs] (each once) that have every word of [query] in
/// their title, artist or album, at most [limit]: what a search that can't
/// reach YouTube Music finds in your library, as Spotify's and YouTube
/// Music's search finds your downloads offline.
List<MediaItem> librarySearchMatches(String query, Iterable<MediaItem> songs,
    {int limit = 50}) {
  if (query.trim().isEmpty) return const [];
  final seen = <String>{};
  final found = <MediaItem>[];
  for (final song in songs) {
    if (!seen.add(song.id)) continue;
    if (!libraryMatches(query, songSearchFields(song))) continue;
    found.add(song);
    if (found.length >= limit) break;
  }
  return found;
}
