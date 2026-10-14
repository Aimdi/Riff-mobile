/// Playlist import from M3U / M3U8 and PLS files, the playlists local
/// players (foobar2000, VLC, Winamp, AIMP, MusicBee, Poweramp), iTunes /
/// Apple Music and Metrolist save. An entry's title ("Artist - Title")
/// or, without one, its file name and folders say what to look for; a
/// YouTube link names the very track.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'csv_playlist_import.dart';
import 'spotify_import_service.dart' show SpotifyTrackRef;
import 'youtube_links.dart';

/// A playlist file's text: UTF-8, or Latin-1 when it isn't (an .m3u from
/// Winamp, a CSV from Excel on Windows), so accented names stay readable.
String decodePlaylistBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// A playlist file of any kind Riff reads: M3U / M3U8, PLS or CSV, by its
/// name's extension or, failing that, its first line. Throws
/// [FormatException] when it's a CSV without a title column.
CsvPlaylist parsePlaylistFile(String fileName, String text) {
  final name = fileName.toLowerCase();
  final body = _withoutBom(text).trimLeft();
  final head = body.substring(0, math.min(body.length, 10)).toLowerCase();
  if (name.endsWith('.m3u') ||
      name.endsWith('.m3u8') ||
      head.startsWith('#extm3u')) {
    return parsePlaylistM3u(text);
  }
  if (name.endsWith('.pls') || head.startsWith('[playlist]')) {
    return parsePlaylistPls(text);
  }
  return parsePlaylistCsv(text);
}

String _withoutBom(String s) => s.startsWith('﻿') ? s.substring(1) : s;

final _lines = RegExp(r'\r\n|\r|\n');

/// Read an M3U / M3U8 playlist: `#PLAYLIST:` names it; `#EXTINF:` (the
/// length in seconds, then "Artist - Title") and `#EXTART:` describe the
/// location after them.
CsvPlaylist parsePlaylistM3u(String text) {
  String? name;
  String? display;
  String? artist;
  int? seconds;
  final tracks = <SpotifyTrackRef>[];
  var skipped = 0;
  for (final raw in _withoutBom(text).split(_lines)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      final tag = line.toUpperCase();
      if (tag.startsWith('#PLAYLIST:')) {
        final n = line.substring(10).trim();
        if (n.isNotEmpty) name = n;
      } else if (tag.startsWith('#EXTINF:')) {
        final info = _extInf(line.substring(8));
        seconds = info.seconds;
        display = info.display;
      } else if (tag.startsWith('#EXTART:')) {
        artist = line.substring(8).trim();
      }
      continue;
    }
    final entry = playlistEntry(tracks.length + skipped + 1,
        location: line, display: display, artist: artist, seconds: seconds);
    if (entry == null) {
      skipped++;
    } else {
      tracks.add(entry);
    }
    display = null;
    artist = null;
    seconds = null;
  }
  return CsvPlaylist(
      format: CsvPlaylistFormat.m3u,
      tracks: tracks,
      name: name,
      skipped: skipped);
}

/// `#EXTINF:` after its colon: the length in seconds (-1 when unknown),
/// maybe attributes (`tvg-name="a, b"`), then a comma and the title.
({int? seconds, String? display}) _extInf(String rest) {
  var inQuotes = false;
  var comma = -1;
  for (var i = 0; i < rest.length; i++) {
    final c = rest[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == ',' && !inQuotes) {
      comma = i;
      break;
    }
  }
  final head = comma < 0 ? rest : rest.substring(0, comma);
  final length = double.tryParse(head.trim().split(RegExp(r'\s+')).first);
  final display = comma < 0 ? '' : rest.substring(comma + 1).trim();
  return (
    seconds: length != null && length > 0 ? length.round() : null,
    display: display.isEmpty ? null : display,
  );
}

/// Read a PLS playlist (`FileN=`, `TitleN=`, `LengthN=`), in the order of
/// its entries' numbers.
CsvPlaylist parsePlaylistPls(String text) {
  final files = <int, String>{};
  final titles = <int, String>{};
  final lengths = <int, int>{};
  final key = RegExp(r'^(file|title|length)(\d+)$', caseSensitive: false);
  for (final raw in _withoutBom(text).split(_lines)) {
    final line = raw.trim();
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final m = key.firstMatch(line.substring(0, eq).trim());
    if (m == null) continue;
    final n = int.parse(m.group(2)!);
    final value = line.substring(eq + 1).trim();
    switch (m.group(1)!.toLowerCase()) {
      case 'file':
        files[n] = value;
      case 'title':
        titles[n] = value;
      case 'length':
        final s = int.tryParse(value);
        if (s != null && s > 0) lengths[n] = s;
    }
  }
  final tracks = <SpotifyTrackRef>[];
  var skipped = 0;
  for (final n in files.keys.toList()..sort()) {
    final entry = playlistEntry(n,
        location: files[n]!, display: titles[n], seconds: lengths[n]);
    if (entry == null) {
      skipped++;
    } else {
      tracks.add(entry);
    }
  }
  return CsvPlaylist(
      format: CsvPlaylistFormat.pls, tracks: tracks, skipped: skipped);
}

/// A track number before a file's title ("01 ", "01 - ", "1-03 ", "3. ").
final _trackNumber =
    RegExp(r'^(?:\d{1,2}-\d{1,3}\s+|\d{1,3}\s*[-._)]\s*|0\d{1,2}\s+)');

/// "12 " before a title, a track number too unless an artist follows
/// ("50 Cent - In Da Club").
final _bareNumber = RegExp(r'^\d{2,3}\s+');

final _extension = RegExp(r'\.[A-Za-z0-9]{1,5}$');

/// Folders that say nothing of who made what's in them (normalized).
const _plainFolders = {
  'sdcard',
  'storage',
  'emulated',
  'mnt',
  'home',
  'users',
  'volumes',
  'music',
  'mymusic',
  'download',
  'downloads',
  'documents',
  'desktop',
  'media',
  'medialocalized',
  'audio',
  'songs',
  'albums',
  'artists',
  'playlists',
  'itunes',
  'itunesmedia',
  'compilations',
  'variousartists',
  'unknownartist',
  'unknownalbum',
};

/// Letters and digits only, lowercase: names compared as people read them.
String _key(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// A file name without its track number.
String _withoutTrackNumber(String name) {
  final sure = _trackNumber.firstMatch(name);
  if (sure != null) return name.substring(sure.end).trim();
  final bare = _bareNumber.firstMatch(name);
  if (bare != null && !name.contains(' - ')) {
    return name.substring(bare.end).trim();
  }
  return name;
}

/// Entry [n] of a playlist file, to look for on YouTube Music: what its
/// [display] title (else its file name) and [artist] say, with its length
/// in [seconds]; a YouTube link at [location] is the track itself. Null
/// when there's nothing to look for (a stream without a title).
SpotifyTrackRef? playlistEntry(int n,
    {required String location, String? display, String? artist, int? seconds}) {
  var path = location;
  String? youtubeId;
  final uri = Uri.tryParse(location);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  if (scheme == 'http' || scheme == 'https') {
    final link = youtubeLinkFrom(uri!);
    if (link.kind == YoutubeLinkKind.song) youtubeId = link.id;
    path = '';
  } else if (scheme == 'file') {
    try {
      path = Uri.decodeFull(uri!.path);
    } on ArgumentError {
      path = uri!.path;
    }
  }
  final folders =
      path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  final file = folders.isEmpty
      ? ''
      : folders.removeLast().replaceFirst(_extension, '').trim();
  final stem = _withoutTrackNumber(file);

  var by = (artist ?? '').trim();
  final shown = (display ?? '').trim();
  var title = shown.isNotEmpty ? shown : stem;
  final first = title.indexOf(' - ');
  if (first > 0) {
    final last = title.lastIndexOf(' - ');
    // "Artist - Title", as most players write it ...
    final artistA = title.substring(0, first).trim();
    final titleA = title.substring(first + 3).trim();
    // ... or "Title - Artist", as iTunes does: the file's own name, or
    // the artist's folder it's in, tells.
    final titleB = title.substring(0, last).trim();
    final artistB = title.substring(last + 3).trim();
    final known = {for (final f in folders) _key(f)};
    final stemKey = _key(stem);
    if (by.isNotEmpty) {
      // The artist said apart (#EXTART) too.
      if (_key(artistA) == _key(by)) {
        title = titleA;
      } else if (_key(artistB) == _key(by)) {
        title = titleB;
      }
    } else if ((_key(titleB) == stemKey && _key(titleA) != stemKey) ||
        (known.contains(_key(artistB)) && !known.contains(_key(artistA)))) {
      by = artistB;
      title = titleB;
    } else {
      by = artistA;
      title = titleA;
    }
  }
  if (by.isEmpty) by = _folderArtist(folders);
  if (title.isEmpty) {
    if (youtubeId == null) return null;
    title = location;
  }
  return SpotifyTrackRef(
    id: 'csv_$n',
    title: title,
    artists: by,
    durationMs: seconds != null && seconds > 0 ? seconds * 1000 : null,
    youtubeId: youtubeId,
  );
}

/// The artist the folders a file is in name (Artist/Album/track or
/// Artist/track); none when they're the phone's own (Music, Download).
String _folderArtist(List<String> folders) {
  bool plain(String f) =>
      _plainFolders.contains(_key(f)) ||
      RegExp(r'^(?:[A-Za-z]:|~|\d+)$').hasMatch(f);
  if (folders.isEmpty || plain(folders.last)) return '';
  if (folders.length >= 2 && !plain(folders[folders.length - 2])) {
    return folders[folders.length - 2];
  }
  return folders.last;
}
