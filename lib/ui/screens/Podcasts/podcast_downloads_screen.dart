import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_progress_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_empty_state.dart';
import 'podcast_layout.dart';
import 'podcast_queue_screen.dart' show showAddToQueueSheet;
import 'podcast_download_undo.dart';

/// AntennaPod-style Downloads hub: list offline episodes and remove them.
class PodcastDownloadsScreen extends StatefulWidget {
  const PodcastDownloadsScreen({super.key, this.onDiscover});

  final VoidCallback? onDiscover;

  @override
  State<PodcastDownloadsScreen> createState() => _PodcastDownloadsScreenState();
}

class _PodcastDownloadsScreenState extends State<PodcastDownloadsScreen> {
  List<MediaItem> _items = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _items = PodcastDownloadService.downloadedItems());
  }

  Future<void> _play(MediaItem item) async {
    if (!Get.isRegistered<PlayerController>()) return;
    final ok = await Get.find<PlayerController>().playPlayListSong([item], 0);
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = _items.isEmpty
        ? PodcastEmptyState(
            icon: Icons.download_outlined,
            message: 'noDownloads'.tr,
            actionLabel: widget.onDiscover != null ? 'discover'.tr : null,
            onAction: widget.onDiscover,
          )
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
            itemCount: _items.length,
            // The rows draw their own hairlines, as Inbox and Queue do.
            itemBuilder: (context, i) {
              final item = _items[i];
              return PodcastEpisodeTile(
                artUrl: Thumbnail(item.artUri?.toString() ?? '').medium,
                title: item.title,
                show: item.artist ?? '',
                meta: episodeMetaLine([
                  episodeDateLabel(item.extras?['date']),
                  episodeTimeLabel(item.id, item.duration?.inSeconds),
                ]),
                progress: PodcastProgressService.progress(item.id),
                onTap: () => _play(item),
                onLongPress: () => showAddToQueueSheet(context, item),
                trailing: IconButton(
                  tooltip: 'removeDownload'.tr,
                  icon: Icon(Icons.delete_outline,
                      size: RiffComponentSizes.trailingIcon,
                      color: theme.colorScheme.onSurfaceVariant),
                  onPressed: () => removePodcastDownloadWithUndo(item.id,
                      context: context, onChanged: () {
                    if (mounted) _reload();
                  }),
                ),
              );
            },
          );

    return body;
  }
}
