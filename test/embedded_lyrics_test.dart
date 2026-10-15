import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/embedded_lyrics.dart';
import 'package:harmonymusic/services/synced_lyrics_service.dart';
import 'package:hive/hive.dart';

List<int> _syncsafe(int n) =>
    [(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F];
List<int> _u32(int n) =>
    [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
List<int> _le32(int n) =>
    [n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF];

List<int> _frame(String id, List<int> data, {required int major}) => [
      ...ascii.encode(id),
      ...(major == 4 ? _syncsafe(data.length) : _u32(data.length)),
      0,
      0,
      ...data,
    ];

Uint8List _tag(int major, List<int> body) => Uint8List.fromList(
    [0x49, 0x44, 0x33, major, 0, 0, ..._syncsafe(body.length), ...body]);

List<int> _utf16(String text) => [
      0xFF,
      0xFE,
      for (final u in text.codeUnits) ...[u & 0xFF, u >> 8],
    ];

/// USLT: encoding, language, description, the lyrics.
List<int> _uslt(String text, {int encoding = 3, String description = ''}) => [
      encoding,
      ...ascii.encode('eng'),
      ...switch (encoding) {
        1 => [..._utf16(description), 0, 0, ..._utf16(text)],
        0 => [...latin1.encode(description), 0, ...latin1.encode(text)],
        _ => [...utf8.encode(description), 0, ...utf8.encode(text)],
      },
    ];

/// SYLT in milliseconds (format 2), lyrics (type 1), UTF-8.
List<int> _sylt(List<(String, int)> lines, {int format = 2}) => [
      3,
      ...ascii.encode('eng'),
      format,
      1,
      0, // no description
      for (final (text, ms) in lines) ...[...utf8.encode(text), 0, ..._u32(ms)],
    ];

/// A FLAC's metadata: STREAMINFO, a big PICTURE, then the comments.
Uint8List _flac(List<String> comments, {int picture = 300000}) {
  List<int> block(int type, List<int> data, {bool last = false}) => [
        (last ? 0x80 : 0) | type,
        (data.length >> 16) & 0xFF,
        (data.length >> 8) & 0xFF,
        data.length & 0xFF,
        ...data,
      ];
  final vendor = utf8.encode('reference libFLAC 1.4.3');
  final body = [
    ..._le32(vendor.length),
    ...vendor,
    ..._le32(comments.length),
    for (final c in comments) ...[
      ..._le32(utf8.encode(c).length),
      ...utf8.encode(c)
    ],
  ];
  return Uint8List.fromList([
    ...ascii.encode('fLaC'),
    ...block(0, List.filled(34, 1)),
    ...block(6, List.filled(picture, 0xAB)),
    ...block(4, body, last: true),
    // The audio.
    ...List.filled(1000, 0xFF),
  ]);
}

const _lrc = '[00:01.00]First line\n[00:04.50]Second line\n[00:09.00]Third';

MediaItem _phoneSong(String id) => MediaItem(
    id: 'device_$id',
    title: 'Song $id',
    extras: {'url': 'content://media/external/audio/media/$id'});

/// Lyrics in your own music files, as Musicolet, Poweramp and Samsung Music
/// show them.
void main() {
  group('an MP3\'s ID3 tag', () {
    test('USLT text: the lyrics as text', () {
      final l = EmbeddedLyrics.fromId3(_tag(4, [
        ..._frame('TIT2', [3, ...utf8.encode('Title')], major: 4),
        ..._frame('APIC', List.filled(2000, 0xAB), major: 4),
        ..._frame('USLT', _uslt('Line one\r\nLine two', description: 'x'),
            major: 4),
      ]))!;
      expect(l.synced, isNull);
      expect(l.plain, 'Line one\nLine two');
    });

    test('USLT holding LRC (LRCGET, Picard): synced, its words as text', () {
      final l = EmbeddedLyrics.fromId3(_tag(3, [
        ..._frame('USLT', _uslt('[ar:Someone]\n$_lrc', encoding: 1), major: 3),
      ]))!;
      expect(l.synced, '[ar:Someone]\n$_lrc');
      expect(l.plain, 'First line\nSecond line\nThird');
    });

    test('SYLT in milliseconds: LRC lines with their times', () {
      final l = EmbeddedLyrics.fromId3(_tag(4, [
        ..._frame(
            'SYLT',
            _sylt([
              ('\nHello', 1000),
              ('world', 61250),
            ]),
            major: 4),
        ..._frame('USLT', _uslt('Hello\nworld', encoding: 0), major: 4),
      ]))!;
      expect(l.synced, '[00:01.00]Hello\n[01:01.25]world');
      expect(l.plain, 'Hello\nworld');
    });

    test('SYLT in MPEG frames can\'t be timed: the text is kept', () {
      final l = EmbeddedLyrics.fromId3(_tag(4, [
        ..._frame('SYLT', _sylt([('Hello', 40)], format: 1), major: 4),
        ..._frame('USLT', _uslt('Hello'), major: 4),
      ]))!;
      expect(l.synced, isNull);
      expect(l.plain, 'Hello');
    });

    test('no lyrics, or no tag: nothing', () {
      expect(
          EmbeddedLyrics.fromId3(_tag(4, [
            ..._frame('TIT2', [3, ...utf8.encode('Title')], major: 4),
            ..._frame('USLT', _uslt('  '), major: 4),
          ])),
          isNull);
      expect(EmbeddedLyrics.fromId3(Uint8List(16)), isNull);
    });
  });

  test('times as LRC writes them', () {
    expect(EmbeddedLyrics.lrcTime(0), '[00:00.00]');
    expect(EmbeddedLyrics.lrcTime(754321), '[12:34.32]');
    expect(EmbeddedLyrics.looksLikeLrc(_lrc), isTrue);
    expect(EmbeddedLyrics.looksLikeLrc('[Chorus]\nLa la\nLa la la'), isFalse);
    expect(
        EmbeddedLyrics.looksLikeLrc(
            '[00:01.00]Only one timed\nthen text\nand more'),
        isFalse);
  });

  group('a phone song\'s file', () {
    late Map<String, Uint8List> files;
    late List<(int, int)> reads;

    setUp(() {
      EmbeddedLyrics.forget();
      files = {};
      reads = [];
      EmbeddedLyrics.reader = (uri, offset, length) async {
        reads.add((offset, length));
        final file = files[uri];
        if (file == null || offset >= file.length) return null;
        return Uint8List.sublistView(
            file, offset, math.min(file.length, offset + length));
      };
    });

    test('a FLAC: its comments read past the cover, not the cover', () async {
      final song = _phoneSong('1');
      files['${song.extras!['url']}'] = _flac([
        'TITLE=Song',
        'lyrics=$_lrc',
        'UNSYNCEDLYRICS=First line\nSecond line\nThird',
      ]);
      final l = (await EmbeddedLyrics.forSong(song))!;
      expect(l.synced, _lrc);
      expect(l.plain, 'First line\nSecond line\nThird');
      // Headers and the comments only: nothing near the cover's size.
      expect(reads.every((r) => r.$2 < 300000), isTrue);

      // Read once.
      reads.clear();
      await EmbeddedLyrics.forSong(song);
      expect(reads, isEmpty);
    });

    test('an MP3: its tag, as long as it says', () async {
      final song = _phoneSong('2');
      final tag = _tag(4, [..._frame('USLT', _uslt('Words'), major: 4)]);
      files['${song.extras!['url']}'] =
          Uint8List.fromList([...tag, ...List.filled(5000, 0xFF)]);
      expect((await EmbeddedLyrics.forSong(song))!.plain, 'Words');
      expect(reads.last, (0, tag.length));
    });

    test('not a phone song, or no lyrics: nothing, nothing read', () async {
      expect(
          await EmbeddedLyrics.forSong(const MediaItem(
              id: 'dQw4w9WgXcQ', title: 'YouTube', extras: {'url': 'x'})),
          isNull);
      expect(reads, isEmpty);

      final song = _phoneSong('3');
      files['${song.extras!['url']}'] = _flac(['TITLE=Song'], picture: 10);
      expect(await EmbeddedLyrics.forSong(song), isNull);
      // An unreadable file: nothing either.
      expect(await EmbeddedLyrics.forSong(_phoneSong('gone')), isNull);
    });

    group('the lyrics shown', () {
      setUp(() async {
        await Hive.openBox('lyrics', bytes: Uint8List(0));
      });
      tearDown(() async => Hive.close());

      test('the file\'s synced lyrics, before any online, and kept', () async {
        final song = _phoneSong('4');
        files['${song.extras!['url']}'] = _tag(4, [
          ..._frame('USLT', _uslt(_lrc), major: 4),
        ]);
        final shown = (await SyncedLyricsService.getSyncedLyrics(song, 200))!;
        expect(shown['synced'], _lrc);
        expect(shown['plainLyrics'], 'First line\nSecond line\nThird');
        expect(shown['source'], 'embedded');
        expect(Hive.box('lyrics').get(song.id)['synced'], _lrc);
      });
    });
  });
}
