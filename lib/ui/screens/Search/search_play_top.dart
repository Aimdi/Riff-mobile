import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '/models/playling_from.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';

/// Songs bucket from [MusicServices.search] (filter: songs).
List<MediaItem> songsFromSearchResult(Map<String, dynamic> result) {
  final raw = result['Songs'];
  if (raw is List) return raw.whereType<MediaItem>().toList();
  return const [];
}

/// Play the top song hit for [query]. Returns false when nothing playable.
Future<bool> playTopSongResult(String query) async {
  final q = query.trim();
  if (q.isEmpty ||
      !Get.isRegistered<MusicServices>() ||
      !Get.isRegistered<PlayerController>()) {
    return false;
  }
  try {
    final result =
        await Get.find<MusicServices>().search(q, filter: 'songs', limit: 5);
    final songs = songsFromSearchResult(result);
    if (songs.isEmpty) return false;
    await Get.find<PlayerController>().playPlayListSong(
      songs,
      0,
      playfrom: PlaylingFrom(
        type: PlaylingFromType.SELECTION,
        name: q,
      ),
    );
    return true;
  } catch (_) {
    return false;
  }
}
