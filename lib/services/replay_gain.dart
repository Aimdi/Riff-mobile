/// ReplayGain: how many dB a song plays louder or quieter to sound as loud
/// as the others, as the tools that tag music libraries write it
/// (foobar2000, MusicBrainz Picard, beets, Mp3tag, Quod Libet) and music
/// servers report it (Navidrome and the other OpenSubsonic servers).
/// Poweramp, Symfonium, foobar2000 and VLC play by it; Riff's loudness
/// normalization does for the songs YouTube doesn't measure.
library;

import 'dart:convert';
import 'dart:typed_data';

import '/services/id3_chapters.dart';
import '/services/vorbis_comments.dart';

class ReplayGain {
  const ReplayGain({this.track, this.album});

  /// The song's own gain, in dB.
  final double? track;

  /// Its album's (the album's songs keep their loudness between them).
  final double? album;

  /// The gain normalization plays by: the song's, else its album's.
  double? get gain => track ?? album;

  /// [gain] as YouTube's loudnessDb, how many dB above YouTube's reference
  /// (−14 LUFS) a song is. ReplayGain brings songs to −18 LUFS (2.0's
  /// reference; 1.0's 89 dB means the same), so a gain of g dB is a song
  /// at −18 − g LUFS: −4 − g above YouTube's.
  static double loudnessDb(double gain) => -4 - gain;

  /// "−6.54 dB", "+2.1 dB", "-6,54": its dB. Null for anything else, or a
  /// gain no song needs (beyond ±64 dB).
  static double? parseGain(Object? text) {
    if (text is num) return _sane(text.toDouble());
    final m = _gainText.firstMatch('${text ?? ''}');
    if (m == null) return null;
    return _sane(double.tryParse(m.group(1)!.replaceAll(',', '.')));
  }

  static final _gainText =
      RegExp(r'^\s*([+-]?\d+(?:[.,]\d+)?)\s*(?:db)?\s*$', caseSensitive: false);

  static double? _sane(double? db) =>
      db == null || db.isNaN || db.abs() > 64 ? null : db;

  static ReplayGain? _of(double? track, double? album) =>
      track == null && album == null
          ? null
          : ReplayGain(track: track, album: album);

  /// The ReplayGain in an ID3v2.3 / 2.4 [tag]: its TXXX frames
  /// (REPLAYGAIN_TRACK_GAIN, REPLAYGAIN_ALBUM_GAIN, in any case), else its
  /// RVA2 frames' master volume ("track", "album").
  static ReplayGain? fromId3(Uint8List tag) {
    double? track, album, rvaTrack, rvaAlbum;
    for (final frame in id3Frames(tag)) {
      if (frame.id == 'TXXX') {
        final field = _txxx(frame.data);
        if (field == null) continue;
        switch (field.$1.trim().toUpperCase()) {
          case 'REPLAYGAIN_TRACK_GAIN':
            track ??= parseGain(field.$2);
          case 'REPLAYGAIN_ALBUM_GAIN':
            album ??= parseGain(field.$2);
        }
      } else if (frame.id == 'RVA2') {
        final rva = _rva2(frame.data);
        if (rva == null) continue;
        if (rva.id == 'album') {
          rvaAlbum ??= rva.db;
        } else {
          rvaTrack ??= rva.db;
        }
      }
    }
    return _of(track, album) ?? _of(rvaTrack, rvaAlbum);
  }

  /// A TXXX frame's description and value.
  static (String, String)? _txxx(Uint8List d) {
    if (d.length < 2) return null;
    final encoding = d[0];
    final end = id3TextEnd(d, 1, encoding);
    if (end == null) return null;
    var value = Uint8List.sublistView(d, end.next);
    // Some writers terminate the value too.
    final valueEnd = id3TextEnd(value, 0, encoding);
    if (valueEnd != null) value = Uint8List.sublistView(value, 0, valueEnd.at);
    return (
      id3Decode(encoding, Uint8List.sublistView(d, 1, end.at)),
      id3Decode(encoding, value),
    );
  }

  /// An RVA2 frame's identification and its master volume's adjustment
  /// (dB × 512, signed), past the other channels' and their peaks.
  static ({String id, double db})? _rva2(Uint8List d) {
    final nul = d.indexOf(0);
    if (nul < 0) return null;
    final id = latin1.decode(Uint8List.sublistView(d, 0, nul)).toLowerCase();
    var at = nul + 1;
    while (at + 4 <= d.length) {
      final adjustment = ByteData.sublistView(d, at + 1, at + 3).getInt16(0);
      if (d[at] == 1) return (id: id.trim(), db: adjustment / 512);
      at += 4 + (d[at + 3] + 7) ~/ 8;
    }
    return null;
  }

  /// The ReplayGain among a Vorbis comment [block]'s fields (a FLAC's).
  static ReplayGain? fromVorbisComments(Uint8List block) {
    double? track, album;
    for (final (key, value) in vorbisComments(block)) {
      if (key == 'REPLAYGAIN_TRACK_GAIN') track ??= parseGain(value);
      if (key == 'REPLAYGAIN_ALBUM_GAIN') album ??= parseGain(value);
    }
    return _of(track, album);
  }

  /// A Subsonic song's replayGain (OpenSubsonic): its trackGain and
  /// albumGain. 0 is what some servers send for a gain they haven't
  /// measured.
  static ReplayGain? fromSubsonic(Object? json) {
    if (json is! Map) return null;
    double? measured(Object? v) {
      final db = parseGain(v);
      return db == 0 ? null : db;
    }

    return _of(measured(json['trackGain']), measured(json['albumGain']));
  }

  /// As a song's extras keep it (a server's song, through playlists and the
  /// saved queue).
  Map<String, double> toJson() => {
        if (track != null) 'track': track!,
        if (album != null) 'album': album!,
      };

  static ReplayGain? fromJson(Object? json) => json is Map
      ? _of(parseGain(json['track']), parseGain(json['album']))
      : null;
}
