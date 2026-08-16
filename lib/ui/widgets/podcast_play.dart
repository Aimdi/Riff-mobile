import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '../../models/playling_from.dart';
import '../../models/thumbnail.dart';
import '../../services/podcast_progress_service.dart';
import '../../services/podcast_service.dart';
import '../player/player_controller.dart';

/// iTunes / RSS show tiles play the feed instead of only opening the list.
bool shouldPlayPodcastShowOnTap() => true;

/// Start at the in-progress episode when we have one, else the newest (0).
int podcastShowStartIndex({
  required List<String> episodeIds,
  required String? inProgressId,
}) {
  final id = inProgressId?.trim() ?? '';
  if (id.isEmpty) return 0;
  final i = episodeIds.indexOf(id);
  return i >= 0 ? i : 0;
}

MediaItem podcastEpisodeToMediaItem(
  Map<String, dynamic> episode,
  Map<String, dynamic> podcast,
) {
  final durationSec = episode['durationSec'];
  final seconds = durationSec is int
      ? durationSec
      : int.tryParse('$durationSec') ?? 0;
  return MediaItem(
    id: '${episode['id']}',
    title: '${episode['title'] ?? 'Episode'}',
    artist: '${podcast['title'] ?? ''}',
    duration: seconds > 0 ? Duration(seconds: seconds) : null,
    artUri: Uri.tryParse(
      Thumbnail(
        (episode['artwork'] ?? podcast['artwork'] ?? '').toString(),
      ).extraHigh,
    ),
    extras: {
      'url': episode['url'],
      'isPodcast': true,
      'description': episode['description'],
      'date': episode['date'],
      'pubDateMs': episode['pubDateMs'] ?? 0,
      'feedUrl': podcast['feedUrl'],
      if (episode['chaptersUrl'] != null) 'chaptersUrl': episode['chaptersUrl'],
      if (episode['transcriptUrl'] != null)
        'transcriptUrl': episode['transcriptUrl'],
      if (episode['transcriptUrl'] != null)
        'transcriptType': episode['transcriptType'],
    },
  );
}

/// Fetch a show's RSS episodes and play from the in-progress (or first) one.
Future<bool> playPodcastShow(Map<String, dynamic> podcast) async {
  final feed = (podcast['feedUrl'] ?? '').toString().trim();
  if (feed.isEmpty || !Get.isRegistered<PlayerController>()) return false;
  final title = (podcast['title'] ?? '').toString();
  final art = (podcast['artwork'] ?? '').toString();
  final raw = await PodcastService.episodes(feed, title, art);
  if (raw.isEmpty) return false;
  final items =
      raw.map((e) => podcastEpisodeToMediaItem(e, podcast)).toList();
  final inProgress = PodcastProgressService.inProgress();
  final startId = inProgress.isNotEmpty ? '${inProgress.first['id']}' : null;
  final index = podcastShowStartIndex(
    episodeIds: items.map((e) => e.id).toList(),
    inProgressId: startId,
  );
  final player = Get.find<PlayerController>();
  final pos = PodcastProgressService.positionMs(items[index].id) ?? 0;
  if (pos > 0) player.armResume(items[index].id, pos);
  await player.playPlayListSong(
    items,
    index,
    playfrom: PlaylingFrom(
      type: PlaylingFromType.SELECTION,
      name: title,
    ),
  );
  return true;
}
