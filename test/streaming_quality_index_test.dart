import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart' show AudioQuality;
import 'package:harmonymusic/services/network_kind.dart';
import 'package:harmonymusic/services/stream_service.dart';

/// One rule for the audio quality, shared by the audio pipeline's stream
/// resolve, its cache bookkeeping and video mode's audio track. Video mode
/// used to read only `streamingQuality`, so with Data saver on it fetched
/// the high-quality audio stream the pipeline itself would not play.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Data saver always means the low-quality stream', () {
    expect(streamingQualityIndex(dataSaver: true, streamingQuality: 1), 0);
    expect(streamingQualityIndex(dataSaver: true, streamingQuality: null), 0);
  });

  test('otherwise the Streaming quality setting, high when unset', () {
    expect(streamingQualityIndex(dataSaver: false, streamingQuality: 0), 0);
    expect(streamingQualityIndex(dataSaver: false, streamingQuality: 1), 1);
    expect(streamingQualityIndex(dataSaver: null, streamingQuality: null), 1);
  });

  test('a malformed stored value falls back to high instead of throwing', () {
    // The handler used to cast it with `as int`.
    expect(streamingQualityIndex(dataSaver: 'yes', streamingQuality: '0'), 1);
    expect(streamingQualityIndex(streamingQuality: 1.0), 1);
  });

  test('Auto: high on Wi-Fi, low on mobile data; Data saver still wins', () {
    expect(AudioQuality.Auto.index, autoStreamingQuality);
    expect(streamingQualityIndex(streamingQuality: autoStreamingQuality), 1);
    expect(
        streamingQualityIndex(
            streamingQuality: autoStreamingQuality, metered: true),
        0);
    expect(
        streamingQualityIndex(
            dataSaver: true, streamingQuality: autoStreamingQuality),
        0);
    // Low and High don't go by the connection.
    expect(streamingQualityIndex(streamingQuality: 1, metered: true), 1);
    expect(streamingQualityIndex(streamingQuality: 0), 0);
  });

  group('the connection', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(NetworkKind.channel, null);
    });

    test("its last answer is kept for what can't wait", () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(
          NetworkKind.channel, (call) async => true);
      await NetworkKind.isMetered();
      expect(NetworkKind.lastMetered, isTrue);
      messenger.setMockMethodCallHandler(
          NetworkKind.channel, (call) async => false);
      await NetworkKind.isMetered();
      expect(NetworkKind.lastMetered, isFalse);
    });
  });
}
