import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/stream_service.dart';

/// One rule for the audio quality, shared by the audio pipeline's stream
/// resolve, its cache bookkeeping and video mode's audio track. Video mode
/// used to read only `streamingQuality`, so with Data saver on it fetched
/// the high-quality audio stream the pipeline itself would not play.
void main() {
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
}
