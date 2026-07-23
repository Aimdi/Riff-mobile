import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/video_stream_service.dart';

/// Mirrors the null-safe Hive → enum mapping used in
/// SettingsScreenController._setInitValue (startup blank-screen fix).
T enumOrDefault<T extends Enum>(List<T> values, dynamic index, T fallback) {
  if (index is int && index >= 0 && index < values.length) {
    return values[index];
  }
  return fallback;
}

void main() {
  group('startup prefs enum mapping', () {
    test('null streamingQuality does not throw and falls back to High', () {
      expect(
        enumOrDefault(AudioQuality.values, null, AudioQuality.High),
        AudioQuality.High,
      );
    });

    test('out-of-range streamingQuality falls back to High', () {
      expect(
        enumOrDefault(AudioQuality.values, -1, AudioQuality.High),
        AudioQuality.High,
      );
      expect(
        enumOrDefault(AudioQuality.values, 99, AudioQuality.High),
        AudioQuality.High,
      );
    });

    test('valid streamingQuality indexes Low/High', () {
      expect(
        enumOrDefault(AudioQuality.values, 0, AudioQuality.High),
        AudioQuality.Low,
      );
      expect(
        enumOrDefault(AudioQuality.values, 1, AudioQuality.High),
        AudioQuality.High,
      );
    });

    test('legacy AudioQuality.values[null] throws (documents crash)', () {
      expect(
        () => AudioQuality.values[null as dynamic],
        throwsA(isA<TypeError>()),
      );
    });

    test('videoQuality null/invalid falls back like settings init', () {
      expect(
        enumOrDefault(VideoQuality.values, null, VideoQuality.high),
        VideoQuality.high,
      );
      expect(
        enumOrDefault(VideoQuality.values, 0, VideoQuality.high),
        VideoQuality.low,
      );
    });
  });
}
