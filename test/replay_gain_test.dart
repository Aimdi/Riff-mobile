import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/cloud_music_service.dart';
import 'package:harmonymusic/services/device_file_tags.dart';
import 'package:harmonymusic/services/embedded_lyrics.dart';
import 'package:harmonymusic/services/normalization_level.dart';
import 'package:harmonymusic/services/own_loudness.dart';
import 'package:harmonymusic/services/replay_gain.dart';

List<int> _syncsafe(int n) =>
    [(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F];
List<int> _u32(int n) =>
    [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
List<int> _le32(int n) =>
    [n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF];

List<int> _frame(String id, List<int> data, {int major = 4}) => [
      ...ascii.encode(id),
      ...(major == 4 ? _syncsafe(data.length) : _u32(data.length)),
      0,
      0,
      ...data,
    ];

Uint8List _tag(List<int> body, {int major = 4}) => Uint8List.fromList(
    [0x49, 0x44, 0x33, major, 0, 0, ..._syncsafe(body.length), ...body]);

List<int> _utf16(String text) => [
      0xFF,
      0xFE,
      for (final u in text.codeUnits) ...[u & 0xFF, u >> 8],
    ];

/// TXXX: encoding, description, value (UTF-8's terminated too, as some
/// writers do).
List<int> _txxx(String description, String value, {int encoding = 3}) => [
      encoding,
      ...switch (encoding) {
        1 => [..._utf16(description), 0, 0, ..._utf16(value)],
        0 => [...latin1.encode(description), 0, ...latin1.encode(value)],
        _ => [...utf8.encode(description), 0, ...utf8.encode(value), 0],
      },
    ];

/// RVA2: identification, then channels (type, dB × 512, 16 peak bits).
List<int> _rva2(String id, double db, {bool frontRightFirst = false}) {
  List<int> channel(int type, int adjustment) =>
      [type, (adjustment >> 8) & 0xFF, adjustment & 0xFF, 16, 0x7F, 0xFF];
  return [
    ...latin1.encode(id),
    0,
    if (frontRightFirst) ...channel(2, 1024),
    ...channel(1, (db * 512).round()),
  ];
}

/// A Vorbis comment block (a FLAC's).
Uint8List _comments(List<String> fields) {
  final vendor = utf8.encode('reference libFLAC 1.4.3');
  return Uint8List.fromList([
    ..._le32(vendor.length),
    ...vendor,
    ..._le32(fields.length),
    for (final f in fields) ...[
      ..._le32(utf8.encode(f).length),
      ...utf8.encode(f)
    ],
  ]);
}

MediaItem _phoneSong(String id) => MediaItem(
    id: 'device_$id',
    title: 'Song $id',
    extras: {'url': 'content://media/external/audio/media/$id'});

/// Normalization for your own music, as Poweramp, Symfonium and foobar2000
/// play it: the ReplayGain your files' tags and your music server carry.
void main() {
  group('a gain', () {
    test('in the forms tags write it', () {
      expect(ReplayGain.parseGain('-6.54 dB'), -6.54);
      expect(ReplayGain.parseGain('+2.10 dB'), 2.1);
      expect(ReplayGain.parseGain(' -7,03 db '), -7.03);
      expect(ReplayGain.parseGain('-3'), -3);
      expect(ReplayGain.parseGain(-1.5), -1.5);
      expect(ReplayGain.parseGain('loud'), isNull);
      expect(ReplayGain.parseGain('-120 dB'), isNull);
      expect(ReplayGain.parseGain(null), isNull);
    });

    test('as YouTube\'s loudness, and the volume a song plays at', () {
      // −18 LUFS, ReplayGain's reference: 4 dB under YouTube's.
      expect(ReplayGain.loudnessDb(0), -4);
      // A loud master (−10 LUFS, a gain of −8 dB), at Normal (−5 dB):
      // lowered 9 dB, as a YouTube song as loud is.
      expect(ReplayGain.loudnessDb(-8), 4);
      expect(normalizedVolume(4, NormalizationLevel.normal.targetDb),
          closeTo(0.355, 0.001));
      // A quiet one can't be raised past full volume.
      expect(normalizedVolume(ReplayGain.loudnessDb(3), -5), 1.0);
      // The track's gain, else its album's.
      expect(const ReplayGain(track: -6, album: -4).gain, -6);
      expect(const ReplayGain(album: -4).gain, -4);
    });
  });

  group('an MP3\'s ID3 tag', () {
    test('TXXX frames, in any case and encoding', () {
      final g = ReplayGain.fromId3(_tag([
        ..._frame('TIT2', [3, ...utf8.encode('Title')]),
        ..._frame('APIC', List.filled(2000, 0xAB)),
        ..._frame('TXXX', _txxx('MusicBrainz Album Id', 'abc')),
        ..._frame('TXXX', _txxx('replaygain_track_gain', '-7.21 dB')),
        ..._frame(
            'TXXX', _txxx('REPLAYGAIN_ALBUM_GAIN', '-6.80 dB', encoding: 1)),
        ..._frame('TXXX', _txxx('REPLAYGAIN_TRACK_PEAK', '0.988', encoding: 0)),
      ]))!;
      expect(g.track, -7.21);
      expect(g.album, -6.8);

      // ID3v2.3, Latin-1 (mp3gain's, older foobar2000's).
      expect(
          ReplayGain.fromId3(_tag([
            ..._frame(
                'TXXX', _txxx('REPLAYGAIN_TRACK_GAIN', '+1.20 dB', encoding: 0),
                major: 3),
          ], major: 3))!
              .gain,
          1.2);
    });

    test('RVA2 (Quod Libet\'s) when there\'s no TXXX: the master volume', () {
      final g = ReplayGain.fromId3(_tag([
        ..._frame('RVA2', _rva2('album', -5.5)),
        ..._frame('RVA2', _rva2('track', -7.5, frontRightFirst: true)),
      ]))!;
      expect(g.track, -7.5);
      expect(g.album, -5.5);
      // TXXX first.
      expect(
          ReplayGain.fromId3(_tag([
            ..._frame('RVA2', _rva2('track', -7.5)),
            ..._frame('TXXX', _txxx('REPLAYGAIN_TRACK_GAIN', '-2 dB')),
          ]))!
              .gain,
          -2);
    });

    test('none, or garbled: nothing', () {
      expect(
          ReplayGain.fromId3(_tag([
            ..._frame('TXXX', _txxx('REPLAYGAIN_TRACK_GAIN', 'n/a')),
            ..._frame('TXXX', _txxx('REPLAYGAIN_TRACK_PEAK', '0.9')),
          ])),
          isNull);
      expect(ReplayGain.fromId3(Uint8List(16)), isNull);
    });
  });

  test('a FLAC\'s comments, in any case', () {
    final g = ReplayGain.fromVorbisComments(_comments([
      'TITLE=Song',
      'replaygain_track_gain=-7.03 dB',
      'REPLAYGAIN_ALBUM_GAIN=-6.50 dB',
    ]))!;
    expect(g.track, -7.03);
    expect(g.album, -6.5);
    expect(ReplayGain.fromVorbisComments(_comments(['TITLE=Song'])), isNull);
  });

  group('a music server\'s songs', () {
    test('OpenSubsonic\'s replayGain; 0 is one not measured', () {
      final g = ReplayGain.fromSubsonic(
          {'trackGain': -7.5, 'albumGain': -6, 'trackPeak': 0.98})!;
      expect(g.track, -7.5);
      expect(g.album, -6);
      expect(ReplayGain.fromSubsonic({'trackGain': 0, 'albumGain': 0}), isNull);
      expect(
          ReplayGain.fromSubsonic({'trackGain': 0, 'albumGain': -6})!.gain, -6);
      expect(ReplayGain.fromSubsonic(null), isNull);
    });

    test('kept with the song through playlists and the saved queue', () {
      final song = CloudSong.fromJson({
        'id': '42',
        'title': 'Song',
        'replayGain': {'trackGain': -7.5, 'albumGain': -6},
      })!;
      expect(song.replayGain!.track, -7.5);
      // As CloudMusicService.toMediaItem keeps it.
      final item = MediaItem(id: 'cloud_42', title: song.title, extras: {
        'url': 'https://music.example/rest/stream.view?id=42',
        'replayGain': song.replayGain!.toJson(),
      });
      final back = MediaItemBuilder.fromJson(
          jsonDecode(jsonEncode(MediaItemBuilder.toJson(item))));
      final g = ReplayGain.fromJson(back.extras!['replayGain'])!;
      expect(g.track, -7.5);
      expect(g.album, -6);

      // A server that doesn't measure: nothing kept.
      expect(
          CloudSong.fromJson({'id': '43', 'title': 'x'})!.replayGain, isNull);
      expect(
          MediaItemBuilder.toJson(const MediaItem(id: 'cloud_43', title: 'x'))
              .containsKey('replayGain'),
          isFalse);
    });
  });

  group('the loudness a song plays by', () {
    late Map<String, Uint8List> files;
    late List<(int, int)> reads;

    setUp(() {
      DeviceFileTags.forget();
      files = {};
      reads = [];
      DeviceFileTags.reader = (uri, offset, length) async {
        reads.add((offset, length));
        final file = files[uri];
        if (file == null || offset >= file.length) return null;
        return Uint8List.sublistView(
            file, offset, math.min(file.length, offset + length));
      };
    });

    test('a phone song\'s: its tags, read once with its lyrics', () async {
      final song = _phoneSong('1');
      files['${song.extras!['url']}'] = _tag([
        ..._frame(
            'USLT', [3, ...ascii.encode('eng'), 0, ...utf8.encode('Words')]),
        ..._frame('TXXX', _txxx('REPLAYGAIN_TRACK_GAIN', '-6.50 dB')),
      ]);
      expect(hasOwnLoudness(song), isTrue);
      // Asked for both at once, as a song starting with its lyrics shown.
      final loudness = ownLoudnessDb(song);
      final lyrics = EmbeddedLyrics.forSong(song);
      expect(await loudness, 2.5);
      expect((await lyrics)!.plain, 'Words');
      expect(reads, [(0, 10), (0, files.values.single.length)]);

      // A FLAC's.
      final flac = _phoneSong('2');
      final block = _comments(['REPLAYGAIN_TRACK_GAIN=+1.00 dB']);
      files['${flac.extras!['url']}'] = Uint8List.fromList([
        ...ascii.encode('fLaC'),
        0x84, // the last block, comments
        ...[(block.length >> 16) & 0xFF, (block.length >> 8) & 0xFF],
        block.length & 0xFF,
        ...block,
      ]);
      expect(await ownLoudnessDb(flac), -5);

      // None in its tags: none.
      final bare = _phoneSong('3');
      files['${bare.extras!['url']}'] = _tag([
        ..._frame('TIT2', [3, ...utf8.encode('Title')]),
      ]);
      expect(await ownLoudnessDb(bare), isNull);
    });

    test('a server song\'s: kept with it, else asked of the server once',
        () async {
      final asked = <String>[];
      Future<ReplayGain?> server(String id) async {
        asked.add(id);
        return const ReplayGain(track: -9);
      }

      const kept = MediaItem(id: 'cloud_1', title: 'Kept', extras: {
        'replayGain': {'track': -7.0}
      });
      expect(await ownLoudnessDb(kept, server: server), 3);
      expect(asked, isEmpty);

      const older = MediaItem(id: 'cloud_2', title: 'Older', extras: {});
      expect(await ownLoudnessDb(older, server: server), 5);
      expect(asked, ['2']);
    });

    test('a YouTube song: none of its own, nothing read or asked', () async {
      const song = MediaItem(
          id: 'dQw4w9WgXcQ', title: 'YouTube', extras: {'url': 'content://x'});
      expect(hasOwnLoudness(song), isFalse);
      expect(
          await ownLoudnessDb(song,
              server: (_) async => fail('asked the server')),
          isNull);
      expect(reads, isEmpty);
    });
  });

  group('the loudness waited for', () {
    test('known in time: before the song is heard', () async {
      final late = <double>[];
      expect(
          await soonOrLate<double>(
              Future.value(2.5), const Duration(milliseconds: 200), late.add),
          2.5);
      expect(late, isEmpty);
    });

    test('a slow read: the song starts, and it applies once known', () async {
      final read = Completer<double?>();
      final late = <double>[];
      expect(
          await soonOrLate(
              read.future, const Duration(milliseconds: 10), late.add),
          isNull);
      read.complete(2.5);
      await Future<void>.delayed(Duration.zero);
      expect(late, [2.5]);

      // Nothing found late: nothing applied.
      final none = Completer<double?>();
      await soonOrLate(none.future, const Duration(milliseconds: 10), late.add);
      none.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(late, [2.5]);
    });
  });
}
