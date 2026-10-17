import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/download_quality.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:hive/hive.dart';

Audio _audio(int itag, Codec codec, int bitrate) => Audio(
    itag: itag,
    audioCodec: codec,
    bitrate: bitrate,
    duration: 200000,
    loudnessDb: 0,
    url: 'https://example.com/$itag',
    size: bitrate * 25);

StreamProvider _streams(List<Audio> formats) =>
    StreamProvider(playable: true, audioFormats: formats);

void main() {
  // As YouTube lists them: each format from its lowest bitrate up.
  final all = _streams([
    _audio(139, Codec.mp4a, 48000),
    _audio(140, Codec.mp4a, 128000),
    _audio(249, Codec.opus, 50000),
    _audio(250, Codec.opus, 70000),
    _audio(251, Codec.opus, 160000),
  ]);

  test('Low: the smallest stream in the download format', () {
    expect(all.lowestBitrateAudioOf(Codec.opus)?.itag, 249);
    expect(all.lowestBitrateAudioOf(Codec.mp4a)?.itag, 139);
    // High is as before: the best of the format.
    expect(all.highestBitrateOpusAudio?.itag, 251);
    expect(all.highestBitrateMp4aAudio?.itag, 140);
  });

  test('without the format, the smallest of any; unknown bitrates last', () {
    final opusOnly = _streams([
      _audio(251, Codec.opus, 160000),
      _audio(250, Codec.opus, 0),
      _audio(249, Codec.opus, 50000),
    ]);
    expect(opusOnly.lowestBitrateAudioOf(Codec.mp4a)?.itag, 249);
    expect(
        _streams([_audio(140, Codec.mp4a, 0)])
            .lowestBitrateAudioOf(Codec.mp4a)
            ?.itag,
        140);
    expect(_streams([]).lowestBitrateAudioOf(Codec.opus), isNull);
  });

  group('the setting', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await DownloadQuality.set(false);
      await Hive.close();
    });

    test('High by default; Low is kept', () async {
      expect(DownloadQuality.low.value, isFalse);
      await DownloadQuality.set(true);
      expect(DownloadQuality.low.value, isTrue);
      expect(Hive.box('AppPrefs').get(DownloadQuality.key), 'low');
    });
  });
}
