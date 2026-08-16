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
  String? name,
  PlaylingFromType type = PlaylingFromType.PLAYLIST,
}) async {
  if (songs.isEmpty || !Get.isRegistered<PlayerController>()) return false;
  await Get.find<PlayerController>().playPlayListSong(
    playQueueFrom(songs, shuffle: shuffle),
    0,
    playfrom: PlaylingFrom(
      type: type,
      name: name ?? 'cloudRandomMix'.tr,
    ),
  );
  return true;
}

/// Fetch a cloud album/playlist and play it. Returns false so the caller
/// can open the collection screen instead.
Future<bool> playCloudCollection({
  required CloudMusicService cloud,
  required String id,
  required bool isPlaylist,
  required String title,
}) async {
  if (!Get.isRegistered<PlayerController>()) return false;
  try {
    final detail =
        isPlaylist ? await cloud.fetchPlaylist(id) : await cloud.fetchAlbum(id);
    if (detail.songs.isEmpty) return false;
    return playCloudSongs(
      cloud.toMediaItems(detail.songs),
      shuffle: false,
      name: title,
      type: isPlaylist ? PlaylingFromType.PLAYLIST : PlaylingFromType.ALBUM,
    );
  } catch (_) {
    return false;
  }
}

/// Re-roll the server mix and start it.
Future<bool> fetchAndPlayCloudRandomMix(CloudMusicService cloud) async {
  await cloud.fetchRandomSongs();
  return playCloudSongs(
    cloud.toMediaItems(cloud.songs.toList()),
    shuffle: true,
  );
}
