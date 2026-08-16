import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Cloud/cloud_play.dart';

void main() {
  test('cloud play bar shows only when connected with songs', () {
    expect(
      shouldShowCloudSongsPlayBar(connected: false, songCount: 8),
      isFalse,
    );
    expect(
      shouldShowCloudSongsPlayBar(connected: true, songCount: 0),
      isFalse,
    );
    expect(
      shouldShowCloudSongsPlayBar(connected: true, songCount: 3),
      isTrue,
    );
  });

  test('playCloudSongs no-ops without a player or songs', () async {
    expect(await playCloudSongs(const [], shuffle: true), isFalse);
    expect(
      await playCloudSongs(
        [const MediaItem(id: 'cloud_1', title: 'A')],
        shuffle: false,
      ),
      isFalse,
    );
  });
}
