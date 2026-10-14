import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_starred.dart';
import '/ui/player/long_form_queue.dart' show episodeNotes;
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_empty_state.dart';
import 'podcast_history_screen.dart' show podcastHistoryState;
import 'podcast_layout.dart';
import 'podcast_queue_screen.dart' show showAddToQueueSheet;

/// Stars [episode], or unstars it with Undo (Pocket Casts' star); the
/// snackbar shows from [context].
Future<void> toggleStarredEpisode(
    BuildContext context, MediaItem episode) async {
  final target = undoSnackbarTarget(context);
  final was = StarredEpisodes.entry(episode.id);
  if (was == null) {
    HapticFeedback.lightImpact();
    // The player's copy may carry shortened notes; keep the full ones.
    final notes = episodeNotes(episode);
    final ok = await StarredEpisodes.star(notes.isEmpty
        ? episode
        : episode.copyWith(extras: {...?episode.extras, 'description': notes}));
    showUndoSnackbar(target, ok ? 'episodeStarred'.tr : 'operationFailed'.tr);
    return;
  }
  await StarredEpisodes.unstar(episode.id);
  showUndoSnackbar(target, 'episodeUnstarred'.tr,
      onUndo: () => StarredEpisodes.restore([was]));
}

/// Episodes you starred, newest first: the Starred tab in Podcasts, like
/// Pocket Casts' Starred, Spotify's Your Episodes and Apple Podcasts'
/// Saved. Tap one to play it from where you were (long-press: its menu),
/// swipe it away to unstar it, with Undo.
class PodcastStarredScreen extends StatelessWidget {
  const PodcastStarredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      StarredEpisodes.rev.value;
      final starred = StarredEpisodes.all;
      if (starred.isEmpty) {
        return PodcastEmptyState(
          icon: Icons.star_outline_rounded,
          message: 'noStarredEpisodes'.tr,
        );
      }
      // The rows draw their own hairlines (§5.2).
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
        itemCount: starred.length,
        itemBuilder: (_, i) => PodcastStarredRow(starred: starred[i]),
      );
    });
  }
}

/// One starred episode: the shared episode row with the show and where it
/// stands (played, time left, or its length).
class PodcastStarredRow extends StatelessWidget {
  const PodcastStarredRow({super.key, required this.starred});
  final StarredEpisode starred;

  @override
  Widget build(BuildContext context) {
    final item = starred.item;
    if (item == null) return const SizedBox.shrink();
    final error = Theme.of(context).colorScheme.error;
    return Dismissible(
      key: ValueKey(starred.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: RiffSpacing.xxl),
        color: error.withOpacity(RiffPalette.swipeRemoveOpacity),
        child: Icon(Icons.star_outline_rounded, color: error),
      ),
      onDismissed: (_) {
        final target = undoSnackbarTarget(context);
        StarredEpisodes.unstar(starred.id);
        showUndoSnackbar(target, 'episodeUnstarred'.tr,
            onUndo: () => StarredEpisodes.restore([starred]));
      },
      child: PodcastEpisodeTile(
        artUrl: Thumbnail(item.artUri?.toString() ?? '').medium,
        title: item.title,
        meta: episodeMetaLine([item.artist, podcastHistoryState(item)]),
        progress: PodcastProgressService.progress(item.id),
        onTap: () => _play(item),
        onLongPress: () => showAddToQueueSheet(context, item),
      ),
    );
  }

  Future<void> _play(MediaItem item) async {
    if (await openInWizeStreamIfPreferred(item)) return;
    final ok = await Get.find<PlayerController>().playPlayListSong([item], 0);
    if (!ok) snackOperationFailed();
  }
}
