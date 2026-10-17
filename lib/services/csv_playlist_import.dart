/// Playlist import from CSV exports: Exportify (Spotify) and TuneMyMusic,
/// plus any CSV with a title and artist column. Columns are found by their
/// header, case-insensitively; an ISRC column is used when present.
library;

import 'spotify_import_service.dart' show SpotifyTrackRef;
import 'youtube_links.dart';

/// Which tool made the file, or which kind of playlist file it is (for the
/// summary only; a CSV is read by its header). M3U and PLS files are read
/// in m3u_playlist_import.dart.
enum CsvPlaylistFormat { exportify, tuneMyMusic, generic, m3u, pls }

class CsvPlaylist {
  const CsvPlaylist(
      {required this.format, required this.tracks, this.name, this.skipped = 0});
  final CsvPlaylistFormat format;
  final List<SpotifyTrackRef> tracks;

  /// Playlist name from the file, when it has one (TuneMyMusic, an M3U's
  /// #PLAYLIST).
  final String? name;

  /// Rows without a title (entries with nothing to look for).
  final int skipped;
}

/// Split CSV text into rows of fields (RFC 4180: quoted fields, doubled
/// quotes, line breaks inside quotes, CRLF, a leading BOM). The delimiter is
/// a comma unless the header line has more semicolons or tabs.
List<List<String>> parseCsv(String text) {
  var s = text;
  if (s.startsWith('﻿')) s = s.substring(1);
  final firstLine = s.split(RegExp(r'\r?\n')).first;
  int count(String c) => c.allMatches(firstLine).length;
  var delim = ',';
  if (count(';') > count(delim)) delim = ';';
  if (count('\t') > count(delim)) delim = '\t';

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < s.length) {
    final c = s[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
      } else {
        field.write(c);
      }
      i++;
      continue;
    }
    if (c == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (c == delim) {
      endField();
    } else if (c == '\r') {
      // \r\n or a lone \r both end the row.
      endRow();
      if (i + 1 < s.length && s[i + 1] == '\n') i++;
    } else if (c == '\n') {
      endRow();
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

String _norm(String h) => h.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int _find(List<String> headers, List<String> names) {
  for (final n in names) {
    final i = headers.indexOf(n);
    if (i >= 0) return i;
  }
  return -1;
}

/// Read a playlist export. Throws [FormatException] when there's no title
/// column.
CsvPlaylist parsePlaylistCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) throw const FormatException('Empty file');
  final headers = [for (final h in rows.first) _norm(h)];

  final title = _find(headers,
      ['track name', 'track', 'title', 'song name', 'song', 'name']);
  final artist = _find(headers, [
    'artist name(s)',
    'artist name',
    'artist names',
    'artists',
    'artist',
  ]);
  final isrc = _find(headers, ['isrc']);
  final durationMs = _find(headers, ['duration (ms)', 'duration_ms']);
  final duration = _find(headers, ['duration', 'length']);
  // A YouTube id or link names the very track (Riff's own export has
  // MediaId).
  final videoId = _find(headers, [
    'mediaid',
    'media id',
    'videoid',
    'video id',
    'youtube id',
    'youtube - id',
    'youtube video id',
  ]);
  final link = _find(headers,
      ['url', 'link', 'youtube url', 'youtube link', 'youtube music url']);
  final spotifyUri = _find(headers,
      ['track uri', 'spotify - id', 'spotify id', 'spotify uri', 'uri']);
  final playlistName =
      _find(headers, ['playlist name', 'playlistname', 'playlist']);
  if (title < 0) {
    throw const FormatException('No track title column');
  }

  final format = headers.contains('artist name(s)') ||
          headers.contains('track uri')
      ? CsvPlaylistFormat.exportify
      : (headers.contains('playlist name') || headers.contains('spotify - id'))
          ? CsvPlaylistFormat.tuneMyMusic
          : CsvPlaylistFormat.generic;

  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

  final tracks = <SpotifyTrackRef>[];
  var skipped = 0;
  String? name;
  for (var n = 1; n < rows.length; n++) {
    final r = rows[n];
    final t = cell(r, title);
    if (t.isEmpty) {
      skipped++;
      continue;
    }
    // Exportify separates artists with commas (older) or semicolons.
    final artists = cell(r, artist)
        .split(RegExp(r'\s*[;|]\s*'))
        .where((a) => a.isNotEmpty)
        .join(', ');
    final ms = durationMs >= 0
        ? int.tryParse(cell(r, durationMs))
        : _lengthMs(cell(r, duration));
    final code = cell(r, isrc).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final uri = cell(r, spotifyUri);
    name ??= cell(r, playlistName).isEmpty ? null : cell(r, playlistName);
    tracks.add(SpotifyTrackRef(
      id: uri.isNotEmpty ? uri : 'csv_$n',
      title: t,
      artists: artists,
      durationMs: ms != null && ms > 0 ? ms : null,
      isrc: isValidIsrc(code) ? code : null,
      youtubeId: _youtubeId(cell(r, videoId), cell(r, link)),
    ));
  }
  return CsvPlaylist(
      format: format, tracks: tracks, name: name, skipped: skipped);
}

final _videoIdShape = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// The YouTube video a row names by its [id] or a [link] to it.
String? _youtubeId(String id, String link) {
  if (_videoIdShape.hasMatch(id)) return id;
  final uri = Uri.tryParse(link);
  if (uri == null || !uri.scheme.startsWith('http')) return null;
  final named = youtubeLinkFrom(uri);
  return named.kind == YoutubeLinkKind.song ? named.id : null;
}

/// A length as a Duration column gives it: "3:45" or "1:02:03" (Riff's
/// own export), else a number, seconds when it's small (under 10000) and
/// milliseconds otherwise.
int? _lengthMs(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  if (v.contains(':')) {
    final parts = v.split(':').map(int.tryParse).toList();
    if (parts.length > 3 || parts.any((p) => p == null || p < 0)) return null;
    final seconds = parts.fold<int>(0, (s, p) => s * 60 + p!);
    return seconds > 0 ? seconds * 1000 : null;
  }
  final n = double.tryParse(v);
  if (n == null || n <= 0) return null;
  return (n < 10000 ? n * 1000 : n).round();
}

/// ISO 3901: 2 letters, 3 alphanumerics, 7 digits.
bool isValidIsrc(String code) =>
    RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$').hasMatch(code);

/// Result of resolving an import, for the summary.
class ImportSummary {
  const ImportSummary({required this.matched, required this.unmatched});
  final int matched;

  /// "Title — Artist" of every track without a match.
  final List<String> unmatched;

  int get total => matched + unmatched.length;
}

/// Matched / unmatched from a resolve result aligned with [tracks].
ImportSummary summarizeImport<T>(
    List<SpotifyTrackRef> tracks, List<T?> resolved) {
  final unmatched = <String>[];
  var matched = 0;
  for (var i = 0; i < tracks.length; i++) {
    if (i < resolved.length && resolved[i] != null) {
      matched++;
    } else {
      final t = tracks[i];
      unmatched.add(t.artists.isEmpty ? t.title : '${t.title} — ${t.artists}');
    }
  }
  return ImportSummary(matched: matched, unmatched: unmatched);
}
