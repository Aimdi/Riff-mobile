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

/// Keyboard submit plays the top hit unless the query is a pasted URL.
bool shouldPlaySearchSubmit(String query) {
  final q = query.trim();
  return q.isNotEmpty && !q.contains('https://');
}

/// Search-bar submit: play the top song, or open results if nothing plays.
Future<bool> submitSearchQuery(
  String val, {
  required void Function(Uri uri) onLink,
  required void Function(String query) onOpenResults,
  required void Function(String query) onRemember,
  void Function()? onAfterSubmit,
}) async {
  final q = val.trim();
  if (q.contains('https://')) {
    onLink(Uri.parse(q));
    onAfterSubmit?.call();
    return false;
  }
  if (q.isEmpty) return false;
  onRemember(q);
  onAfterSubmit?.call();
  final ok = await playTopSongResult(q);
  if (!ok) onOpenResults(q);
  return ok;
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
