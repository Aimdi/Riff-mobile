/// Lyrics a music file on the phone carries in its tags, as Musicolet,
/// Poweramp and Samsung Music show them: an MP3's ID3 USLT frames (text,
/// LRC lines with their times when synced) and SYLT frames (synced), and
/// a FLAC's LYRICS / SYNCEDLYRICS / UNSYNCEDLYRICS comments. They show
/// with no connection, and before any looked up online.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '/services/device_file_tags.dart';
import '/services/id3_chapters.dart';
import '/services/vorbis_comments.dart';

class EmbeddedLyrics {
  const EmbeddedLyrics({this.synced, this.plain});

  /// Synced lyrics, as LRC lines ("[01:02.50]words").
  final String? synced;

  /// Lyrics as text.
  final String? plain;

  /// What [song]'s file carries, when it's one of the phone's music files
  /// (Songs › On this phone); null when it carries none.
  static Future<EmbeddedLyrics?> forSong(MediaItem song) async =>
      (await DeviceFileTags.forSong(song))?.lyrics;

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
    String? synced;
    String? plain;
    for (final (name, value) in vorbisComments(block)) {
      final key = name.replaceAll(' ', '');
      if (key != 'LYRICS' && key != 'SYNCEDLYRICS' && key != 'UNSYNCEDLYRICS') {
        continue;
      }
      final text = _clean(value);
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
      final end = id3TextEnd(rest, 0, encoding);
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
    final end = id3TextEnd(d, from, encoding);
    return end == null ? null : Uint8List.sublistView(d, end.next);
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
