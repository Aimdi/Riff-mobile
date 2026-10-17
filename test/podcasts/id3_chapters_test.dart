import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/id3_chapters.dart';

List<int> _syncsafe(int n) =>
    [(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F];
List<int> _u32(int n) =>
    [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];

List<int> _frame(String id, List<int> data,
        {required int major, bool plainSize = false}) =>
    [
      ...ascii.encode(id),
      ...(major == 4 && !plainSize
          ? _syncsafe(data.length)
          : _u32(data.length)),
      0,
      0,
      ...data,
    ];

/// A TIT2 body: encoding 0 ISO-8859-1, 1 UTF-16 with a BOM, 2 UTF-16BE,
/// 3 UTF-8.
List<int> _title(String text, int encoding) => [
      encoding,
      ...switch (encoding) {
        0 => latin1.encode(text),
        1 => [
            0xFF,
            0xFE,
            for (final u in text.codeUnits) ...[u & 0xFF, u >> 8],
          ],
        2 => [
            for (final u in text.codeUnits) ...[u >> 8, u & 0xFF],
          ],
        _ => utf8.encode(text),
      },
    ];

List<int> _chap(String id, int startMs, int endMs, List<int> frames) => [
      ...latin1.encode(id),
      0,
      ..._u32(startMs),
      ..._u32(endMs),
      ..._u32(0xFFFFFFFF),
      ..._u32(0xFFFFFFFF),
      ...frames,
    ];

Uint8List _tag(int major, List<int> body, {int flags = 0, int padding = 0}) {
  final all = [...body, ...List.filled(padding, 0)];
  return Uint8List.fromList(
      [0x49, 0x44, 0x33, major, 0, flags, ..._syncsafe(all.length), ...all]);
}

void main() {
  test('v2.4: chapters in time order, with titles, ends and links', () {
    const m = 4;
    final tag = _tag(
        m,
        [
          ..._frame('TIT2', _title('The episode', 3), major: m),
          // Cover art first, as most tags have it.
          ..._frame('APIC', List.filled(5000, 0xAB), major: m),
          ..._frame('CTOC', [0x74, 0x6F, 0x63, 0, 3, 2], major: m),
          ..._frame(
              'CHAP',
              _chap('ch2', 754000, 1800000, [
                ..._frame('TIT2', _title('Interview – Ada', 3), major: m),
                ..._frame(
                    'WXXX', [0, 0, ...latin1.encode('https://ada.example')],
                    major: m),
              ]),
              major: m),
          ..._frame(
              'CHAP',
              _chap('ch1', 0, 754000,
                  _frame('TIT2', _title('Intro', 0), major: m)),
              major: m),
        ],
        padding: 64);
    final chapters = parseId3Chapters(tag);
    expect(chapters.map((c) => c.title), ['Intro', 'Interview – Ada']);
    expect(chapters.map((c) => c.startSec), [0, 754]);
    expect(chapters.map((c) => c.endSec), [754, 1800]);
    expect(chapters[1].linkUrl, 'https://ada.example');
    expect(chapters[0].linkUrl, isNull);
  });

  test('v2.3: UTF-16 titles, an extended header', () {
    const m = 3;
    final frames = [
      ..._frame(
          'CHAP',
          _chap(
              'a', 0, 0xFFFFFFFF, _frame('TIT2', _title('Café', 1), major: m)),
          major: m),
      ..._frame('CHAP',
          _chap('b', 61500, 0, _frame('TIT2', _title('Ünïcode', 2), major: m)),
          major: m),
    ];
    // Extended header: its size (6, not counting itself), flags, padding.
    final tag = _tag(m, [..._u32(6), 0, 0, ..._u32(0), ...frames], flags: 0x40);
    final chapters = parseId3Chapters(tag);
    expect(chapters.map((c) => c.title), ['Café', 'Ünïcode']);
    expect(chapters.map((c) => c.startSec), [0, 61.5]);
    // No end given.
    expect(chapters.map((c) => c.endSec), [null, null]);
  });

  test('v2.3 unsynchronised as a whole', () {
    const m = 3;
    // A start of 0xFF00 ms has the FF 00 that unsynchronisation escapes.
    final frames = _frame('CHAP',
        _chap('a', 0xFF00, 0, _frame('TIT2', _title('Escaped', 0), major: m)),
        major: m);
    final unsynced = <int>[];
    for (var i = 0; i < frames.length; i++) {
      unsynced.add(frames[i]);
      if (frames[i] == 0xFF &&
          (i + 1 == frames.length ||
              frames[i + 1] == 0 ||
              frames[i + 1] >= 0xE0)) {
        unsynced.add(0);
      }
    }
    final chapters = parseId3Chapters(_tag(m, unsynced, flags: 0x80));
    expect(chapters.single.title, 'Escaped');
    expect(chapters.single.startSec, 0xFF00 / 1000);
  });

  test('v2.4 frames some writers size plainly still read', () {
    const m = 4;
    final tag = _tag(m, [
      // 256 bytes, written as a plain integer (syncsafe would say 128).
      ..._frame('APIC', List.filled(256, 0xAB), major: m, plainSize: true),
      ..._frame(
          'CHAP',
          _chap('a', 1000, 2000,
              _frame('TIT2', _title('After art', 3), major: m)),
          major: m),
    ]);
    expect(parseId3Chapters(tag).single.title, 'After art');
  });

  test('a tag cut short by the read limit keeps the chapters it has', () {
    const m = 4;
    final whole = _tag(m, [
      ..._frame('CHAP',
          _chap('a', 0, 1000, _frame('TIT2', _title('One', 3), major: m)),
          major: m),
      ..._frame('CHAP',
          _chap('b', 1000, 2000, _frame('TIT2', _title('Two', 3), major: m)),
          major: m),
    ]);
    final cut = Uint8List.sublistView(whole, 0, whole.length - 5);
    expect(parseId3Chapters(cut).single.title, 'One');
  });

  test('not an ID3v2.3 / 2.4 tag: no chapters', () {
    expect(id3TagLength(latin1.encode('RIFF....WAVEfmt ')), isNull);
    final v22 = Uint8List.fromList([0x49, 0x44, 0x33, 2, 0, 0, 0, 0, 0, 10]);
    expect(id3TagLength(v22), isNull);
    expect(parseId3Chapters(v22), isEmpty);
    expect(parseId3Chapters(Uint8List(4)), isEmpty);
  });

  test('only feed episodes are looked at: never music, never YouTube',
      () async {
    // Nothing here could be fetched: these must not try.
    expect(
        await Id3Chapters.forEpisode(const MediaItem(
            id: 'song',
            title: 'Song',
            extras: {'url': 'https://a.example/1.mp3'})),
        isEmpty);
    expect(
        await Id3Chapters.forEpisode(const MediaItem(
            id: 'yt123', title: 'Episode', extras: {'isPodcast': true})),
        isEmpty);
  });

  group('reading the tag', () {
    Stream<List<int>> inChunks(List<int> bytes, int size) async* {
      for (var i = 0; i < bytes.length; i += size) {
        yield bytes.sublist(
            i, i + size > bytes.length ? bytes.length : i + size);
      }
    }

    test("no further than it, when the server sends the whole episode",
        () async {
      final tag =
          _tag(4, _frame('TIT2', _title('Ep', 3), major: 4), padding: 30);
      final episode = [...tag, ...List.filled(100000, 0x55)];
      var chunksRead = 0;
      Stream<List<int>> counted() async* {
        await for (final c in inChunks(episode, 7)) {
          chunksRead++;
          yield c;
        }
      }

      final read = await readId3Tag(counted());
      expect(read, tag);
      expect(chunksRead, lessThan(20));
    });

    test('nothing for audio with no tag, or too little to tell', () async {
      expect(await readId3Tag(inChunks(List.filled(5000, 0xFF), 512)), isNull);
      expect(await readId3Tag(inChunks([0x49, 0x44, 0x33], 3)), isNull);
    });
  });
}
