import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/media_item_video.dart';
import 'package:harmonymusic/utils/youtube_channel_url.dart';

void main() {
  MediaItem item({
    String id = 'abc',
    String? videoType,
    String? resultType,
    bool? isPodcast,
    bool? showVideo,
    String? podcastSource,
  }) {
    return MediaItem(
      id: id,
      title: 'T',
      extras: {
        if (videoType != null) 'videoType': videoType,
        if (resultType != null) 'resultType': resultType,
        if (isPodcast != null) 'isPodcast': isPodcast,
        if (showVideo != null) 'showVideo': showVideo,
        if (podcastSource != null) 'podcastSource': podcastSource,
      },
    );
  }

  group('isYoutubeVideo', () {
    test('ATV songs are not videos', () {
      expect(item(videoType: 'MUSIC_VIDEO_TYPE_ATV').isYoutubeVideo, isFalse);
      expect(item(resultType: 'song').isYoutubeVideo, isFalse);
    });

    test('OMV / UGC / resultType video are videos', () {
      expect(item(videoType: 'MUSIC_VIDEO_TYPE_OMV').isYoutubeVideo, isTrue);
      expect(item(videoType: 'MUSIC_VIDEO_TYPE_UGC').isYoutubeVideo, isTrue);
      expect(item(resultType: 'video').isYoutubeVideo, isTrue);
    });

    test('podcast videoType alone is not isYoutubeVideo', () {
      expect(
        item(videoType: 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE').isYoutubeVideo,
        isFalse,
      );
    });
  });

  group('canShowPlayerVideo', () {
    test('music videos can show video', () {
      expect(item(videoType: 'MUSIC_VIDEO_TYPE_OMV').canShowPlayerVideo, isTrue);
      expect(item(resultType: 'video').canShowPlayerVideo, isTrue);
    });

    test('YTM podcast episodes are audio-first (no video)', () {
      expect(
        item(
          videoType: 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
          isPodcast: true,
          podcastSource: 'yt_music_podcast',
          showVideo: true,
        ).canShowPlayerVideo,
        isFalse,
      );
    });

    test('yt_channel episodes are audio-first (no video)', () {
      expect(
        item(
          videoType: 'MUSIC_VIDEO_TYPE_UGC',
          isPodcast: true,
          podcastSource: 'yt_channel',
          showVideo: true,
        ).canShowPlayerVideo,
        isFalse,
      );
    });

    test('RSS podcasts never show video', () {
      expect(
        item(
          id: 'podcast_123',
          isPodcast: true,
          showVideo: true,
        ).canShowPlayerVideo,
        isFalse,
      );
    });
  });

  group('YoutubeChannelUrl', () {
    test('parses bare UC id and channel URLs', () {
      expect(
        YoutubeChannelUrl.tryChannelId('UCuAXFkgsw1L7xaCfnd5JJOw'),
        'UCuAXFkgsw1L7xaCfnd5JJOw',
      );
      expect(
        YoutubeChannelUrl.tryChannelId(
            'https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw'),
        'UCuAXFkgsw1L7xaCfnd5JJOw',
      );
      expect(
        YoutubeChannelUrl.tryChannelId(
            'https://music.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw/videos'),
        'UCuAXFkgsw1L7xaCfnd5JJOw',
      );
    });

    test('parses handles', () {
      expect(YoutubeChannelUrl.tryHandle('@veritasium'), 'veritasium');
      expect(
        YoutubeChannelUrl.tryHandle('https://www.youtube.com/@veritasium'),
        'veritasium',
      );
    });
  });
}
