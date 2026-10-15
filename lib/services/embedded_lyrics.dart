/// Lyrics a music file on the phone carries in its tags, as Musicolet,
/// Poweramp and Samsung Music show them: an MP3's ID3 USLT frames (text,
/// LRC lines with their times when synced) and SYLT frames (synced), and
/// a FLAC's LYRICS / SYNCEDLYRICS / UNSYNCEDLYRICS comments. They show
/// with no connection, and before any looked up online.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '/services/device_music.dart';
import '/services/id3_chapters.dart';
import '/utils/helper.dart';

/// The most of a tag read for its lyrics (cover art can make it big).
const embeddedLyricsReadLimit = 8 * 1024 * 1024;

class EmbeddedLyrics {
  const EmbeddedLyrics({this.synced, this.plain});

  /// Synced lyrics, as LRC lines ("[01:02.50]words").
  final String? synced;

  /// Lyrics as text.
  final String? plain;

  /// [length] bytes of the file at [uri] from [offset] (fewer at its end;
  /// null when it can't be read). Tests swap it.
  @visibleForTesting
  static Future<Uint8List?> Function(String uri, int offset, int length)
      reader = DeviceMusic.read;

  static final _cache = <String, EmbeddedLyrics?>{};

  @visibleForTesting
  static void forget() => _cache.clear();

  /// What [song]'s file carries, when it's one of the phone's music files
  /// (Songs › On this phone); null when it carries none.
  static Future<EmbeddedLyrics?> forSong(MediaItem song) async {
    if (!DeviceMusic.isDeviceSong(song)) return null;
    final uri = '${song.extras?['url'] ?? ''}';
    if (!uri.startsWith('content://')) return null;
    if (_cache.containsKey(uri)) return _cache[uri];
    EmbeddedLyrics? found;
    try {
      found = await _read(uri);
    } catch (e) {
      printERROR('Lyrics in the file ($uri): $e');
    }
    return _cache[uri] = found;
  }

  static Future<EmbeddedLyrics?> _read(String uri) async {
    final head = await reader(uri, 0, 10);
    if (head == null || head.length < 10) return null;
    final tagLength = id3TagLength(head);
    if (tagLength != null) {
      final tag =
          await reader(uri, 0, math.min(tagLength, embeddedLyricsReadLimit));
      return tag == null ? null : fromId3(tag);
    }
    // "fLaC"
    if (head[0] == 0x66 &&
        head[1] == 0x4C &&
        head[2] == 0x61 &&
        head[3] == 0x43) {
      return _flac(uri);
    }
    return null;
  }

  /// A FLAC's Vorbis comment block, found among its metadata blocks (the
  /// pictures in between skipped, not read).
  static Future<EmbeddedLyrics?> _flac(String uri) async {
    var at = 4;
    for (var blocks = 0; blocks < 64; blocks++) {
      final header = await reader(uri, at, 4);
      if (header == null || header.length < 4) return null;
      final last = header[0] & 0x80 != 0;
      final type = header[0] & 0x7F;
      final length = (header[1] << 16) | (header[2] << 8) | header[3];
      if (type == 4) {
        if (length > embeddedLyricsReadLimit) return null;
        final block = await reader(uri, at + 4, length);
        return block == null ? null : fromVorbisComments(block);
      }
      if (last) return null;
      at += 4 + length;
    }
    return null;
  }

  /// The lyrics in an ID3v2.3 / 2.4 [tag]: a SYLT frame's in milliseconds,
  /// else the USLT frames' (LRC ones as synced).
  static EmbeddedLyrics? fromId3(Uint8List tag) {
    String? synced;
    String? plain;
    for (final frame in id3Frames(tag)) {
      if (frame.id == 'SYLT') {
        synced ??= _sylt(frame.data);
      } else if (frame.id == 'USLT') {
        final text = _uslt(frame.data);
        if (text == null) continue;
        if (looksLikeLrc(text)) {
          synced ??= text;
        } else {
          plain ??= text;
        }
      }
    }
    return _found(synced, plain);
  }

  /// The lyrics among a Vorbis comment [block]'s fields (FLAC, as
  /// MusicBrainz Picard, foobar2000, Mp3tag and LRCGET write them).
  static EmbeddedLyrics? fromVorbisComments(Uint8List block) {
    final b = ByteData.sublistView(block);
    if (block.length < 8) return null;
    var at = 4 + b.getUint32(0, Endian.little);
    if (at + 4 > block.length) return null;
    final count = b.getUint32(at, Endian.little);
    at += 4;
    String? synced;
    String? plain;
    for (var i = 0; i < count && at + 4 <= block.length; i++) {
      final length = b.getUint32(at, Endian.little);
      at += 4;
      if (at + length > block.length) break;
      final field = utf8.decode(Uint8List.sublistView(block, at, at + length),
          allowMalformed: true);
      at += length;
      final eq = field.indexOf('=');
      if (eq <= 0) continue;
      final key = field.substring(0, eq).toUpperCase().replaceAll(' ', '');
      if (key != 'LYRICS' && key != 'SYNCEDLYRICS' && key != 'UNSYNCEDLYRICS') {
        continue;
      }
      final text = _clean(field.substring(eq + 1));
      if (text == null) continue;
      if (looksLikeLrc(text)) {
        synced ??= text;
      } else {
        plain ??= text;
      }
    }
    return _found(synced, plain);
  }

  static EmbeddedLyrics? _found(String? synced, String? plain) =>
      synced == null && plain == null
          ? null
          : EmbeddedLyrics(synced: synced, plain: plain ?? _lrcText(synced!));

  /// A USLT frame's text: after its encoding, language and description.
  static String? _uslt(Uint8List d) {
    if (d.length < 5) return null;
    final encoding = d[0];
    final text = _afterTerminated(d, 4, encoding);
    if (text == null) return null;
    return _clean(id3Decode(encoding, text));
  }

  /// A SYLT frame's lines as LRC (times in milliseconds only; MPEG frame
  /// counts can't be told without the audio).
  static String? _sylt(Uint8List d) {
    if (d.length < 7 || d[4] != 2) return null;
    final encoding = d[0];
    var rest = _afterTerminated(d, 6, encoding);
    final lines = <String>[];
    while (rest != null && rest.isNotEmpty) {
      final end = _terminator(rest, 0, encoding);
      if (end == null || end.next + 4 > rest.length) break;
      final text = id3Decode(encoding, Uint8List.sublistView(rest, 0, end.at))
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim();
      final ms =
          ByteData.sublistView(rest, end.next, end.next + 4).getUint32(0);
      lines.add('${lrcTime(ms)}$text');
      rest = Uint8List.sublistView(rest, end.next + 4);
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// The bytes after the text terminated in [encoding] that starts at
  /// [from] (a description); null when it isn't terminated.
  static Uint8List? _afterTerminated(Uint8List d, int from, int encoding) {
    final end = _terminator(d, from, encoding);
    return end == null ? null : Uint8List.sublistView(d, end.next);
  }

  /// Where the text from [from] ends ([at]) and what follows its
  /// terminator ([next]): one zero byte, or two on a two-byte boundary in
  /// UTF-16.
  static ({int at, int next})? _terminator(
      Uint8List d, int from, int encoding) {
    if (encoding == 1 || encoding == 2) {
      for (var i = from; i + 1 < d.length; i += 2) {
        if (d[i] == 0 && d[i + 1] == 0) return (at: i, next: i + 2);
      }
      return null;
    }
    final i = d.indexOf(0, from);
    return i < 0 ? null : (at: i, next: i + 1);
  }

  static String? _clean(String text) {
    final t = text.replaceAll('\u0000', '').replaceAll('\r\n', '\n').trim();
    return t.isEmpty ? null : t;
  }

  /// LRC's time tag for [ms]: "[01:02.50]".
  @visibleForTesting
  static String lrcTime(int ms) {
    final cs = (ms ~/ 10) % 100;
    final s = (ms ~/ 1000) % 60;
    final m = ms ~/ 60000;
    String two(int n) => n.toString().padLeft(2, '0');
    return '[${two(m)}:${two(s)}.${two(cs)}]';
  }

  static final _timed = RegExp(r'^\s*(\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\])+');

  /// Lyrics as LRC: most of the lines that have words start with a time.
  static bool looksLikeLrc(String text) {
    var timed = 0;
    var lines = 0;
    for (final line in const LineSplitter().convert(text)) {
      final l = line.trim();
      if (l.isEmpty) continue;
      // [ar:…], [ti:…] and other LRC headers don't count either way.
      if (RegExp(r'^\[[a-zA-Z]+:.*\]$').hasMatch(l)) continue;
      lines++;
      if (_timed.hasMatch(l)) timed++;
    }
    return timed >= 2 && timed * 2 > lines;
  }

  /// LRC's words, without their times and headers.
  static String? _lrcText(String lrc) => _clean(const LineSplitter()
      .convert(lrc)
      .map((l) => l.replaceFirst(_timed, '').trim())
      .where((l) => !RegExp(r'^\[[a-zA-Z]+:.*\]$').hasMatch(l))
      .join('\n'));
}
