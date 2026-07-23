import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/media_item_video.dart';

void main() {
  MediaItem item({String? videoType, String? resultType}) {
    return MediaItem(
      id: 'abc',
      title: 'T',
      extras: {
        if (videoType != null) 'videoType': videoType,
        if (resultType != null) 'resultType': resultType,
      },
    );
  }

  test('ATV songs are not videos', () {
    expect(item(videoType: 'MUSIC_VIDEO_TYPE_ATV').isYoutubeVideo, isFalse);
    expect(item(resultType: 'song').isYoutubeVideo, isFalse);
  });

  test('OMV / UGC / resultType video are videos', () {
    expect(item(videoType: 'MUSIC_VIDEO_TYPE_OMV').isYoutubeVideo, isTrue);
    expect(item(videoType: 'MUSIC_VIDEO_TYPE_UGC').isYoutubeVideo, isTrue);
    expect(item(resultType: 'video').isYoutubeVideo, isTrue);
  });

  test('podcasts are not videos', () {
    expect(
      item(videoType: 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE').isYoutubeVideo,
      isFalse,
    );
  });
}
