import 'package:flutter_test/flutter_test.dart';

import 'package:harmonymusic/services/video_stream_service.dart';

void main() {
  group('VideoStreamService.pickBestForPlayer', () {
    test('prefers low-res video-only over muxed 360p', () {
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
        const VideoStreamInfo(
          url: 'mux720',
          width: 1280,
          height: 720,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
      ]);
      expect(pick?.url, 'vo240');
    });

    test('prefers 144p video-only over 240p muxed', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'mux240',
          width: 426,
          height: 240,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
        const VideoStreamInfo(
          url: 'vo144',
          width: 256,
          height: 144,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
      ]);
      expect(pick?.url, 'vo144');
    });

    test('prefers mp4 over webm at same height', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'webm240',
          width: 426,
          height: 240,
          mimeType: 'video/webm',
          hasAudio: false,
        ),
        const VideoStreamInfo(
          url: 'mp4240',
          width: 426,
          height: 240,
          mimeType: 'video/mp4',
          hasAudio: false,
        ),
      ]);
      expect(pick?.url, 'mp4240');
    });

    test('falls back to lowest muxed when no video-only', () {
      final pick = VideoStreamService.pickBestForPlayer([
        const VideoStreamInfo(
          url: 'mux720',
          width: 1280,
          height: 720,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
        const VideoStreamInfo(
          url: 'mux360',
          width: 640,
          height: 360,
          mimeType: 'video/mp4',
          hasAudio: true,
        ),
      ]);
      expect(pick?.url, 'mux360');
    });

    test('returns null for empty list', () {
      expect(VideoStreamService.pickBestForPlayer(const []), isNull);
    });
  });
}
