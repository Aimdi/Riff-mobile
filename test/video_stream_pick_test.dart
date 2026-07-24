import 'package:flutter_test/flutter_test.dart';

import 'package:harmonymusic/services/video_stream_service.dart';

void main() {
  group('VideoStreamService.pickBestForPlayer low (data saver, ≤480p)', () {
    test('picks best video-only within the 480p cap', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'vo240',
          width: 426,
          height: 240,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
        const VideoStreamInfo(
          url: 'vo480',
          width: 854,
          height: 480,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
        const VideoStreamInfo(
          url: 'vo720',
          width: 1280,
          height: 720,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
      ], quality: VideoQuality.low);
      expect(pick?.url, 'vo480');
    });

    test('never picks muxed when any video-only exists', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'mux360',
          width: 640,
          height: 360,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
        const VideoStreamInfo(
          url: 'vo240',
          width: 426,
          height: 240,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
      ], quality: VideoQuality.low);
      expect(pick?.url, 'vo240');
    });

    test('returns null for empty list', () {
      expect(VideoStreamService.pickBestForPlayer(const []), isNull);
    });
  });

  group('VideoStreamService.pickBestForPlayer high (full quality, ≤1080p)',
      () {
    test('picks 1080p video-only — no artificial 720p cap', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'vo720',
          width: 1280,
          height: 720,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
        const VideoStreamInfo(
          url: 'vo1080',
          width: 1920,
          height: 1080,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
        const VideoStreamInfo(
          url: 'vo1440',
          width: 2560,
          height: 1440,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
      ], quality: VideoQuality.high);
      expect(pick?.url, 'vo1080');
    });

    test('prefers video-only over higher muxed', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'mux1080',
          width: 1920,
          height: 1080,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
        const VideoStreamInfo(
          url: 'vo720',
          width: 1280,
          height: 720,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
      ], quality: VideoQuality.high);
      expect(pick?.url, 'vo720');
    });

    test('prefers mp4/avc over av1 at the same height', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'av1_1080',
          width: 1920,
          height: 1080,
          mimeType: 'video/mp4; codecs=av01.0.08M.08',
          hasAudio: false,
        ),
        const VideoStreamInfo(
          url: 'avc1080',
          width: 1920,
          height: 1080,
          mimeType: 'video/mp4; codecs=avc1.640028',
          hasAudio: false,
        ),
      ], quality: VideoQuality.high);
      expect(pick?.url, 'avc1080');
    });

    test('falls back to muxed when no video-only exists', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'mux360',
          width: 640,
          height: 360,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
        const VideoStreamInfo(
          url: 'mux720',
          width: 1280,
          height: 720,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
      ], quality: VideoQuality.high);
      expect(pick?.url, 'mux720');
    });
  });
}
