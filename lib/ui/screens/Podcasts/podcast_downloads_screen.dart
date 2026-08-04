import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import 'podcast_empty_state.dart';
import 'podcast_queue_screen.dart' show showAddToQueueSheet;

/// AntennaPod-style Downloads hub: list offline episodes and remove them.
class PodcastDownloadsScreen extends StatefulWidget {
  const PodcastDownloadsScreen({
    super.key,
    this.embedded = false,
    this.onDiscover,
  });

  final bool embedded;
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

  void _play(MediaItem item) {
    if (!Get.isRegistered<PlayerController>()) return;
    Get.find<PlayerController>().playPlayListSong([item], 0);
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
            padding: const EdgeInsets.only(bottom: 200),
            itemCount: _items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) {
              final item = _items[i];
              final art = Thumbnail(item.artUri?.toString() ?? '').medium;
              final dur = item.duration != null
                  ? PodcastService.formatDuration(item.duration!.inSeconds)
                  : null;
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: art.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: art,
                          width: 48,
                          height: 48,
                          memCacheWidth:
                              (48 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.offline_pin_outlined,
                                color: theme.colorScheme.secondary),
                          ),
                        )
                      : SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.offline_pin_outlined,
                              color: theme.colorScheme.secondary),
                        ),
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
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await PodcastDownloadService.delete(item.id);
                    _reload();
                  },
                ),
              );
            },
          );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text('downloads'.tr)),
      body: body,
    );
  }
}
