import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_history.dart';
import '/services/podcast_progress_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/snackbar.dart';
import '../Home/home_layout.dart';
import 'podcast_empty_state.dart';
import 'podcast_layout.dart';
import 'podcast_queue_screen.dart' show showAddToQueueSheet;

/// Episodes played, newest first, by day: the History tab in Podcasts, like
/// AntennaPod's Playback history and Pocket Casts' Listening history. Tap
/// one to play it from where you were (long-press: Up Next), swipe it away
/// to take it out; Clear history empties it. Both with Undo.
class PodcastHistoryScreen extends StatelessWidget {
  const PodcastHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      PodcastHistory.rev.value;
      final entries = PodcastHistory.all;
      if (entries.isEmpty) {
        return PodcastEmptyState(
          icon: Icons.history_rounded,
          message: 'noListeningHistory'.tr,
        );
      }
      final days = podcastHistoryByDay(entries, DateTime.now());
      return CustomScrollView(
        slivers: [
          for (var d = 0; d < days.length; d++) ...[
            SliverToBoxAdapter(
              child: HomeSectionHeader(
                days[d].$1,
                trailing: d == 0 ? _clearButton(context, entries) : null,
              ),
            ),
            SliverList.separated(
              itemCount: days[d].$2.length,
              // Full-width hairline between rows (§5.2).
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => PodcastHistoryRow(entry: days[d].$2[i]),
            ),
          ],
          const SliverToBoxAdapter(
              child: SizedBox(height: RiffSpacing.listEnd)),
        ],
      );
    });
  }

  /// As compact as the header it sits in.
  Widget _clearButton(BuildContext context, List<PodcastHistoryEntry> all) =>
      TextButton(
        onPressed: () {
          final target = undoSnackbarTarget(context);
          PodcastHistory.clear();
          showUndoSnackbar(target, 'historyCleared'.tr,
              onUndo: () => PodcastHistory.restore(all));
        },
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(
              horizontal: RiffSpacing.md, vertical: RiffSpacing.xs),
        ),
        child: Text('clearHistory'.tr),
      );
}

/// One episode of the history: the shared episode row with the show and
/// where it stands (played, time left, or its length).
class PodcastHistoryRow extends StatelessWidget {
  const PodcastHistoryRow({super.key, required this.entry});
  final PodcastHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    if (item == null) return const SizedBox.shrink();
    final error = Theme.of(context).colorScheme.error;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: RiffSpacing.xxl),
        color: error.withOpacity(RiffPalette.swipeRemoveOpacity),
        child: Icon(Icons.delete_outline_rounded, color: error),
      ),
      onDismissed: (_) {
        final target = undoSnackbarTarget(context);
        PodcastHistory.remove(entry.id);
        showUndoSnackbar(target, 'removedFromHistory'.tr,
            onUndo: () => PodcastHistory.restore([entry]));
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

/// "Played", "25m left" while partly played, else the episode's length.
String podcastHistoryState(MediaItem item) {
  if (PodcastProgressService.isPlayed(item.id)) return 'historyPlayed'.tr;
  final total = item.duration?.inSeconds ?? 0;
  final left = PodcastProgressService.remainingSec(item.id);
  if (left != null && left > 0 && (total <= 0 || left < total)) {
    return '${compactEpisodeLength(left)} ${'left'.tr}';
  }
  return compactEpisodeLength(total);
}
