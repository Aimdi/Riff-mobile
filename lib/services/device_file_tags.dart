import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '/services/device_music.dart';
import '/services/embedded_lyrics.dart';
import '/services/id3_chapters.dart';
import '/services/replay_gain.dart';
import '/utils/helper.dart';

/// The most of a tag read (cover art can make it big).
const deviceTagReadLimit = 8 * 1024 * 1024;

/// What a music file on the phone says of itself in its tags, read once
/// per file: the lyrics it carries, and its ReplayGain for loudness
/// normalization. An MP3's ID3v2.3 / 2.4 tag, a FLAC's Vorbis comments.
class DeviceFileTags {
  const DeviceFileTags({this.lyrics, this.replayGain});

  final EmbeddedLyrics? lyrics;
  final ReplayGain? replayGain;

  /// [length] bytes of the file at [uri] from [offset] (fewer at its end;
  /// null when it can't be read). Tests swap it.
  @visibleForTesting
  static Future<Uint8List?> Function(String uri, int offset, int length)
      reader = DeviceMusic.read;

  /// By file, its read: what asks while it's under way waits for the same
  /// one. The files read last are kept.
  static final _reads = <String, Future<DeviceFileTags?>>{};
  static const _kept = 200;

  @visibleForTesting
  static void forget() => _reads.clear();

  /// What [song]'s file says, when it's one of the phone's music files
  /// (Songs › On this phone); null when it says nothing of the kind.
  static Future<DeviceFileTags?> forSong(MediaItem song) {
    if (!DeviceMusic.isDeviceSong(song)) return Future.value();
    final uri = '${song.extras?['url'] ?? ''}';
    if (!uri.startsWith('content://')) return Future.value();
    final known = _reads.remove(uri);
    if (known != null) return _reads[uri] = known;
    if (_reads.length >= _kept) _reads.remove(_reads.keys.first);
    return _reads[uri] = _read(uri).catchError((Object e) {
      printERROR('Tags of the file ($uri): $e');
      return null;
    });
  }

  static Future<DeviceFileTags?> _read(String uri) async {
    final head = await reader(uri, 0, 10);
    if (head == null || head.length < 10) return null;
    final tagLength = id3TagLength(head);
    if (tagLength != null) {
      final tag = await reader(uri, 0, math.min(tagLength, deviceTagReadLimit));
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
  static Future<DeviceFileTags?> _flac(String uri) async {
    var at = 4;
    for (var blocks = 0; blocks < 64; blocks++) {
      final header = await reader(uri, at, 4);
      if (header == null || header.length < 4) return null;
      final last = header[0] & 0x80 != 0;
      final type = header[0] & 0x7F;
      final length = (header[1] << 16) | (header[2] << 8) | header[3];
      if (type == 4) {
        if (length > deviceTagReadLimit) return null;
        final block = await reader(uri, at + 4, length);
        return block == null ? null : fromVorbisComments(block);
      }
      if (last) return null;
      at += 4 + length;
    }
    return null;
  }

  static DeviceFileTags? fromId3(Uint8List tag) =>
      _found(EmbeddedLyrics.fromId3(tag), ReplayGain.fromId3(tag));

  static DeviceFileTags? fromVorbisComments(Uint8List block) => _found(
      EmbeddedLyrics.fromVorbisComments(block),
      ReplayGain.fromVorbisComments(block));

  static DeviceFileTags? _found(EmbeddedLyrics? lyrics, ReplayGain? gain) =>
      lyrics == null && gain == null
          ? null
          : DeviceFileTags(lyrics: lyrics, replayGain: gain);
}
