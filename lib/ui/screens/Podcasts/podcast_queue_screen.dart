import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_queue_controller.dart';

/// Long-press action sheet for a podcast episode: add it to (or remove it
/// from) the Queue.
void showAddToQueueSheet(BuildContext context, MediaItem episode) {
  final c = Get.find<PodcastQueueController>();
  final queued = c.isQueued(episode.id);
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading:
                Icon(queued ? Icons.playlist_remove : Icons.playlist_add),
            title: Text(queued ? "removeFromQueue".tr : "addToQueue".tr),
            onTap: () {
              queued ? c.removeById(episode.id) : c.add(episode);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(snackbar(
                  context, queued ? "removedFromQueue".tr : "addedToQueue".tr,
                  size: SanckBarSize.MEDIUM));
            },
          ),
        ],
      ),
    ),
  );
}

/// The podcast Queue ("Warteschlange"): episodes you've added via long-press,
/// played in order. Reorder by dragging the handle, swipe/remove to drop one,
/// tap to play from that point.
class PodcastQueueScreen extends StatelessWidget {
  const PodcastQueueScreen({super.key, this.embedded = false});

  /// When true, render just the content (no Scaffold/AppBar) for inline use.
  final bool embedded;

  static String _fmtTotal(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m";
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PodcastQueueController>();
    final body = Obx(() {
      final items = controller.queue;
      if (items.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "queueEmpty".tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "${items.length} ${'episodes'.tr}  ·  "
                    "${'remainingTime'.tr} ${_fmtTotal(controller.totalTime)}",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                // Non-embedded gets the clear action in the AppBar instead.
                if (embedded)
                  IconButton(
                    tooltip: "clear".tr,
                    icon: const Icon(Icons.clear_all, size: 22),
                    onPressed: controller.clear,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 200),
              itemCount: items.length,
              onReorder: controller.reorder,
              itemBuilder: (context, i) =>
                  _row(context, controller, items[i], i),
            ),
          ),
        ],
      );
    });
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text("queue".tr),
        actions: [
          Obx(() => controller.queue.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: "clear".tr,
                  icon: const Icon(Icons.clear_all),
                  onPressed: controller.clear,
                )),
        ],
      ),
      body: body,
    );
  }

  Widget _row(BuildContext context, PodcastQueueController controller,
      MediaItem e, int i) {
    final date = (e.extras?['date'] ?? '').toString().trim();
    final durationText = PodcastService.formatDuration(e.duration?.inSeconds ?? 0);
    final art = Thumbnail(e.artUri?.toString() ?? '').medium;
    return Padding(
      key: ValueKey(e.id),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: InkWell(
        onTap: () =>
            Get.find<PlayerController>().playPlayListSong(items(controller), i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator, size: 22),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: art,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.podcasts, size: 36),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (date.isNotEmpty || durationText.isNotEmpty)
                      Text(
                        [date, durationText].where((s) => s.isNotEmpty)
                            .join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(
                      e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: "removeFromQueue".tr,
                icon: const Icon(Icons.remove_circle_outline, size: 22),
                onPressed: () => controller.removeAt(i),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MediaItem> items(PodcastQueueController c) => c.queue.toList();
}
