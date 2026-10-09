import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_empty_state.dart';
import 'podcast_queue_screen.dart' show showAddToQueueSheet;

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
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
            itemCount: _items.length,
            // Full-width hairline between episodes (§5.2).
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = _items[i];
              final art = Thumbnail(item.artUri?.toString() ?? '').medium;
              final dur = item.duration != null
                  ? PodcastService.formatDuration(item.duration!.inSeconds)
                  : null;
              final fallback = SizedBox.square(
                dimension: RiffComponentSizes.rowArt,
                child: Icon(Icons.offline_pin_outlined,
                    color: theme.colorScheme.onSurfaceVariant),
              );
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(RiffRadii.sm),
                  child: art.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: art,
                          width: RiffComponentSizes.rowArt,
                          height: RiffComponentSizes.rowArt,
                          memCacheWidth: (RiffComponentSizes.rowArt *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => fallback,
                        )
                      : fallback,
                ),
                title: Text(item.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if ((item.artist ?? '').isNotEmpty) item.artist!,
                    if (dur != null) dur,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _play(item),
                onLongPress: () => showAddToQueueSheet(context, item),
                trailing: IconButton(
                  tooltip: 'removeDownload'.tr,
                  icon: Icon(Icons.delete_outline,
                      size: RiffComponentSizes.trailingIcon,
                      color: theme.colorScheme.onSurfaceVariant),
                  onPressed: () async {
                    await PodcastDownloadService.delete(item.id);
                    _reload();
                  },
                ),
              );
            },
          );

    return body;
  }
}
