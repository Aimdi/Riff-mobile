import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playling_from.dart';
import '/services/discovery/discovery_types.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/snackbar.dart';

/// Snackbar when Enter or a suggestion tap could not start playback.
String searchPlayFailedMessageKey() => 'searchPlayFailed';

void showSearchPlayFailed(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(snackbar(
    context,
    searchPlayFailedMessageKey().tr,
    size: SanckBarSize.MEDIUM,
  ));
}

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

/// History and suggestion rows use the same play-first path as Enter.
bool shouldPlaySearchItemOnTap() => true;

/// Tell the user when Enter / row-tap could not start a song.
bool shouldNotifySearchPlayFailed({required bool played}) => !played;

/// Search-bar submit: play the top song, or open results if nothing plays.
Future<bool> submitSearchQuery(
  String val, {
  required void Function(Uri uri) onLink,
  required void Function(String query) onOpenResults,
  required void Function(String query) onRemember,
  void Function()? onAfterSubmit,
  void Function()? onPlayFailed,
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
  if (!ok) {
    if (shouldNotifySearchPlayFailed(played: ok)) {
      onPlayFailed?.call();
    }
    onOpenResults(q);
  }
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
    return Get.find<PlayerController>().playPlayListSong(
      songs,
      0,
      playfrom: PlaylingFrom(
        type: PlaylingFromType.SELECTION,
        name: q,
      ),
      source: DiscoverySource.search,
    );
  } catch (_) {
    return false;
  }
}
