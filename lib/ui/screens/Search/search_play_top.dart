import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playling_from.dart';
import '/services/discovery/discovery_types.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/snackbar.dart';

/// Snackbar when a song picked from search could not start.
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

/// Search-bar submit (Enter, the mic, a search or history row): opens the
/// results for the query, as Spotify, YouTube Music and Apple Music do; a
/// link is opened instead. Nothing plays until you pick a result.
void submitSearchQuery(
  String val, {
  required void Function(String text) onLink,
  required void Function(String query) onOpenResults,
  required void Function(String query) onRemember,
  void Function()? onAfterSubmit,
}) {
  final q = val.trim();
  if (q.contains('https://')) {
    onLink(q);
    onAfterSubmit?.call();
    return;
  }
  if (q.isEmpty) return;
  onRemember(q);
  onAfterSubmit?.call();
  onOpenResults(q);
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
