/// Chapters an episode's MP3 carries in its ID3 tag (CHAP frames, as
/// Auphonic, Hindenburg, Forecast and Ferrite write them), which Overcast,
/// Pocket Casts, Apple Podcasts and AntennaPod read: for episodes whose
/// feed gives none.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';

import '/models/media_item_extras.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_service.dart' show PodcastChapter;
import '/utils/helper.dart';

/// The most of a tag read for its chapters: chapter art can make a tag
/// big, and the episode streams the same bytes again.
const id3ReadLimit = 4 * 1024 * 1024;

class Id3Chapters {
  Id3Chapters._();

  static final _cache = <String, List<PodcastChapter>>{};

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    followRedirects: true,
    headers: {'user-agent': 'Riff/1.0 (podcast)'},
  ));

  /// [episode]'s chapters from its MP3's ID3 tag: read from its download
  /// when there is one, else from the start of its audio. [] when it has
  /// none, or isn't a feed's episode.
  static Future<List<PodcastChapter>> forEpisode(MediaItem episode) async {
    if (!episode.isPodcastEpisode) return const [];
    final local = PodcastDownloadService.localPath(episode.id);
    final remote =
        '${episode.extras?['remoteUrl'] ?? episode.extras?['url'] ?? ''}';
    if (local == null && !remote.startsWith('http')) return const [];
    final key = local ?? remote;
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final tag = local != null
          ? await readId3Tag(File(local).openRead(0, id3ReadLimit))
          : await _remoteTag(remote);
      return _cache[key] = tag == null ? const [] : parseId3Chapters(tag);
    } catch (e) {
      printERROR('ID3 chapters ($key): $e');
      return const [];
    }
  }

  static Future<Uint8List?> _remoteTag(String url) async {
    final cancel = CancelToken();
    try {
      final res = await _dio.get<ResponseBody>(url,
          options: Options(
              responseType: ResponseType.stream,
              headers: {'range': 'bytes=0-${id3ReadLimit - 1}'}),
          cancelToken: cancel);
      final body = res.data;
      return body == null ? null : await readId3Tag(body.stream);
    } finally {
      // Read what the tag needed: the rest of the episode isn't wanted.
      cancel.cancel();
    }
  }
}

/// The ID3 tag [bytes] start with (no more than [id3ReadLimit] of it),
/// reading no further than it: a server can ignore the range asked for
/// and send the whole episode. Null when they don't start with one.
Future<Uint8List?> readId3Tag(Stream<List<int>> bytes) async {
  final read = BytesBuilder(copy: false);
  int? want;
  await for (final chunk in bytes) {
    read.add(chunk);
    if (want == null && read.length >= 10) {
      final length = id3TagLength(read.toBytes());
      if (length == null) return null;
      want = math.min(length, id3ReadLimit);
    }
    if (want != null && read.length >= want) break;
  }
  if (want == null) return null;
  final tag = read.takeBytes();
  return tag.length > want ? Uint8List.sublistView(tag, 0, want) : tag;
}

/// The length of the ID3 tag [header] starts (its own 10 bytes and the
/// size it gives), or null when it isn't an ID3v2.3 / 2.4 one: only those
/// have chapters.
int? id3TagLength(List<int> header) {
  if (header.length < 10) return null;
  // "ID3"
  if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) return null;
  if (header[3] != 3 && header[3] != 4) return null;
  final size = _syncsafe(header, 6);
  return size == null ? null : 10 + size;
}

/// The chapters (CHAP frames) in an ID3v2.3 / 2.4 [tag], by start time:
/// their titles (TIT2) and links (WXXX).
List<PodcastChapter> parseId3Chapters(Uint8List tag) {
  final length = id3TagLength(tag);
  if (length == null) return const [];
  final major = tag[3];
  final flags = tag[5];
  var frames = Uint8List.sublistView(tag, 10, math.min(length, tag.length));
  // A 2.3 tag unsynchronised as a whole.
  if (major == 3 && flags & 0x80 != 0) frames = _resync(frames);
  var at = 0;
  if (flags & 0x40 != 0) {
    // An extended header: 2.4 counts its own size field, 2.3 doesn't.
    if (frames.length < 4) return const [];
    at = major == 4
        ? _syncsafe(frames, 0) ?? frames.length
        : 4 + _uint32(frames, 0);
  }
  final chapters = <PodcastChapter>[];
  for (final frame in _frames(frames, at, major)) {
    if (frame.id != 'CHAP') continue;
    final chapter = _chapter(frame.data, major);
    if (chapter != null) chapters.add(chapter);
  }
  chapters.sort((a, b) => a.startSec.compareTo(b.startSec));
  return chapters;
}

class _Frame {
  const _Frame(this.id, this.data);
  final String id;
  final Uint8List data;
}

/// The frames in [b] from [at], until padding, a frame cut short (the
/// read limit) or anything that isn't one.
Iterable<_Frame> _frames(Uint8List b, int at, int major) sync* {
  while (at + 10 <= b.length && _isFrameId(b, at)) {
    final id = String.fromCharCodes(b, at, at + 4);
    final start = at + 10;
    final plain = _uint32(b, at + 4);
    var size = major == 4 ? _syncsafe(b, at + 4) : plain;
    // Some 2.4 writers give plain sizes: take the one a next frame
    // follows.
    if (size == null ||
        (size != plain &&
            !_frameFollows(b, start + size) &&
            _frameFollows(b, start + plain))) {
      size = plain;
    }
    final end = start + size;
    if (end > b.length) return;
    final formatFlags = b[at + 9];
    at = end;
    var data = Uint8List.sublistView(b, start, end);
    if (major == 4) {
      // Compressed or encrypted: not ours to read.
      if (formatFlags & 0x0C != 0) continue;
      if (formatFlags & 0x40 != 0) data = _skip(data, 1); // group
      if (formatFlags & 0x01 != 0) data = _skip(data, 4); // data length
      if (formatFlags & 0x02 != 0) data = _resync(data);
    } else {
      if (formatFlags & 0xC0 != 0) continue;
      if (formatFlags & 0x20 != 0) data = _skip(data, 1); // group
    }
    yield _Frame(id, data);
  }
}

/// A chapter from a CHAP frame's [d]: its element id, start and end (ms),
/// byte offsets, then frames of its own.
PodcastChapter? _chapter(Uint8List d, int major) {
  final nul = d.indexOf(0);
  if (nul < 0 || nul + 17 > d.length) return null;
  final startMs = _uint32(d, nul + 1);
  final endMs = _uint32(d, nul + 5);
  var title = '';
  String? link;
  for (final sub in _frames(Uint8List.sublistView(d, nul + 17), 0, major)) {
    if (sub.id == 'TIT2' && title.isEmpty) {
      title = _text(sub.data);
    } else if (sub.id == 'WXXX') {
      link ??= _userLink(sub.data);
    }
  }
  return PodcastChapter(
    startSec: startMs / 1000,
    endSec: endMs > startMs && endMs != 0xFFFFFFFF ? endMs / 1000 : null,
    title: title.trim(),
    linkUrl: link,
  );
}

/// A text frame's (first) text, after its encoding byte.
String _text(Uint8List d) {
  if (d.isEmpty) return '';
  return _decode(d[0], Uint8List.sublistView(d, 1)).split('\u0000').first;
}

/// A WXXX frame's web address: after its encoding byte and a description
/// in that encoding, ISO-8859-1.
String? _userLink(Uint8List d) {
  if (d.isEmpty) return null;
  var i = 1;
  if (d[0] == 1 || d[0] == 2) {
    while (i + 1 < d.length && (d[i] != 0 || d[i + 1] != 0)) {
      i += 2;
    }
    i += 2;
  } else {
    while (i < d.length && d[i] != 0) {
      i++;
    }
    i += 1;
  }
  if (i >= d.length) return null;
  final url =
      latin1.decode(Uint8List.sublistView(d, i)).split('\u0000').first.trim();
  return url.startsWith('http://') || url.startsWith('https://') ? url : null;
}

String _decode(int encoding, Uint8List b) => switch (encoding) {
      // UTF-16 with a byte order mark.
      1 => b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF
          ? _utf16(b, 2, littleEndian: false)
          : _utf16(b, b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE ? 2 : 0,
              littleEndian: true),
      2 => _utf16(b, 0, littleEndian: false),
      3 => utf8.decode(b, allowMalformed: true),
      _ => latin1.decode(b),
    };

String _utf16(Uint8List b, int from, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = from; i + 1 < b.length; i += 2) {
    units.add(littleEndian ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// Undoes unsynchronisation: 0xFF 0x00 was 0xFF.
Uint8List _resync(Uint8List b) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < b.length; i++) {
    out.addByte(b[i]);
    if (b[i] == 0xFF && i + 1 < b.length && b[i + 1] == 0) i++;
  }
  return out.takeBytes();
}

Uint8List _skip(Uint8List b, int n) =>
    Uint8List.sublistView(b, math.min(n, b.length));

bool _isFrameId(Uint8List b, int at) {
  for (var i = at; i < at + 4; i++) {
    final c = b[i];
    final upper = c >= 0x41 && c <= 0x5A;
    final digit = c >= 0x30 && c <= 0x39;
    if (!upper && !digit) return false;
  }
  return true;
}

/// Whether a frame (or padding, or the end) can start at [at].
bool _frameFollows(Uint8List b, int at) =>
    at == b.length ||
    (at < b.length && b[at] == 0) ||
    (at + 4 <= b.length && _isFrameId(b, at));

int? _syncsafe(List<int> b, int at) {
  var v = 0;
  for (var i = at; i < at + 4; i++) {
    if (b[i] & 0x80 != 0) return null;
    v = (v << 7) | b[i];
  }
  return v;
}

int _uint32(List<int> b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
