import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '/models/playling_from.dart';
import '/services/cloud_music_service.dart';
import '/ui/player/play_queue_order.dart';
import '/ui/player/player_controller.dart';

/// Cloud Songs tab can play when connected and a slice is loaded.
bool shouldShowCloudSongsPlayBar({
  required bool connected,
  required int songCount,
}) =>
    connected && songCount > 0;

/// Play the current cloud song list (optionally shuffled).
Future<bool> playCloudSongs(
  List<MediaItem> songs, {
  required bool shuffle,
}) async {
  if (songs.isEmpty || !Get.isRegistered<PlayerController>()) return false;
  await Get.find<PlayerController>().playPlayListSong(
    playQueueFrom(songs, shuffle: shuffle),
    0,
    playfrom: PlaylingFrom(
      type: PlaylingFromType.PLAYLIST,
      name: 'cloudRandomMix'.tr,
    ),
  );
  return true;
}

/// Re-roll the server mix and start it.
Future<bool> fetchAndPlayCloudRandomMix(CloudMusicService cloud) async {
  await cloud.fetchRandomSongs();
  return playCloudSongs(
    cloud.toMediaItems(cloud.songs.toList()),
    shuffle: true,
  );
}
