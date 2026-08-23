import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/podcast_service.dart';
import 'podcast_cover_tile.dart';
import 'podcast_empty_state.dart';
import 'podcast_folder_controller.dart';
import 'podcast_folder_screen.dart';
import 'podcasts_library_controller.dart';

/// Long-press a podcast show anywhere it's listed to file it into folders.
/// Reused by the Subscriptions screen and the main Podcasts library grid.
void showPodcastFolderSheet(BuildContext context, Playlist podcast) {
  final fc = Get.find<PodcastFolderController>();
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => SafeArea(
      child: Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${'addToFolder'.tr} · ${podcast.title}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              if (fc.folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: Text('noFoldersYet'.tr,
                      style: Theme.of(ctx).textTheme.bodySmall),
                ),
              ...fc.folders.map((f) => CheckboxListTile(
                    value: fc.contains(f.id, podcast.playlistId),
                    onChanged: (_) => fc.toggle(f.id, podcast.playlistId),
                    title: Text(f.name),
                    secondary: Icon(Icons.folder_rounded, color: f.color),
                  )),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text("newFolder".tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showNewPodcastFolderDialog(context,
                      assignPodcastId: podcast.playlistId);
                },
              ),
            ],
          )),
    ),
  );
}

void showNewPodcastFolderDialog(BuildContext context,
    {String? assignPodcastId}) {
  final fc = Get.find<PodcastFolderController>();
  final ctrl = TextEditingController();
  var colorIndex = 0;
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text("newFolder".tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "folderName".tr,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Text("folderColor".tr,
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              _FolderColorPicker(
                selected: colorIndex,
                onChanged: (i) => setLocal(() => colorIndex = i),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text("cancel".tr)),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                final f = fc.createFolder(name, colorIndex: colorIndex);
                if (assignPodcastId != null) {
                  fc.toggle(f.id, assignPodcastId);
                }
              }
              Navigator.of(ctx).pop();
            },
            child: Text("create".tr),
          ),
        ],
      ),
    ),
  );
}

class _FolderColorPicker extends StatelessWidget {
  const _FolderColorPicker({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < PodcastFolderColors.swatches.length; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: PodcastFolderColors.swatches[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == i
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: selected == i
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Subscriptions ("Abonnements"): a 2-column grid of large covers with a
/// play button on each tile (AntennaPod-style). Folders come first;
/// long-press a show to file it, long-press a folder to delete it.
class PodcastSubsScreen extends StatelessWidget {
  const PodcastSubsScreen({super.key, this.embedded = false, this.onDiscover});

  /// Jumps to the Discover tab (embedded mode) from the empty state.
  final VoidCallback? onDiscover;

  /// When true, render just the content (no Scaffold/AppBar) for inline use.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LibraryPodcastsController>();
    final folders = Get.find<PodcastFolderController>();
    final content = Obx(() {
        final subs = controller.libraryPodcasts.toList();
        // iTunes/RSS subscriptions (followed from Discover) live in a separate
        // store; list them alongside the YouTube-Music library shows.
        PodcastService.subsRev.value; // rebuild when RSS subs change
        final rssSubs = PodcastService.subscriptions;
        final folderList = folders.folders.toList();
        if (subs.isEmpty && rssSubs.isEmpty && folderList.isEmpty) {
          return PodcastEmptyState(
            icon: Icons.subscriptions_outlined,
            message: "noPodcastsBookmarked".tr,
            actionLabel: onDiscover != null ? 'discover'.tr : null,
            onAction: onDiscover,
          );
        }
        return LayoutBuilder(builder: (context, constraints) {
          final total = folderList.length + subs.length + rssSubs.length;
          return GridView.builder(
            padding: kPodcastSubsGridPadding,
            gridDelegate: podcastSubsGridDelegate(constraints.maxWidth),
            itemCount: total,
            itemBuilder: (context, index) {
              if (index < folderList.length) {
                return _folderTile(context, folders, folderList[index]);
              }
              final subIndex = index - folderList.length;
              if (subIndex < subs.length) {
                final podcast = subs[subIndex];
                return PodcastCoverTile(
                  title: podcast.title,
                  subtitle: libraryPodcastSubtitle(podcast),
                  playlist: podcast,
                  imageUrl: podcast.thumbnailUrl,
                  badge: isYoutubeChannelPodcast(podcast)
                      ? youtubeChannelBadge()
                      : null,
                  onTap: () => playLibraryPodcast(podcast),
                  onPlay: () => playLibraryPodcast(podcast),
                  onLongPress: () =>
                      showPodcastFolderSheet(context, podcast),
                );
              }
              final rss = rssSubs[subIndex - subs.length];
              return PodcastCoverTile(
                title: (rss['title'] ?? '').toString(),
                subtitle: (rss['author'] ?? '').toString(),
                imageUrl: rssArtworkUrl(rss),
                onTap: () => playOrOpenRssPodcast(rss),
                onPlay: () => playOrOpenRssPodcast(rss),
                onLongPress: () => _confirmUnfollowRss(context, rss),
              );
            },
          );
        });
    });
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "New folder" only makes sense once something can be filed —
          // don't float a lone action over the empty state.
          Obx(() {
            PodcastService.subsRev.value;
            final hasAny = controller.libraryPodcasts.isNotEmpty ||
                PodcastService.subscriptions.isNotEmpty ||
                folders.folders.isNotEmpty;
            if (!hasAny) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showNewPodcastFolderDialog(context),
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                label: Text("newFolder".tr),
              ),
            );
          }),
          Expanded(child: content),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text("subscriptions".tr),
        actions: [
          IconButton(
            tooltip: "newFolder".tr,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => showNewPodcastFolderDialog(context),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _folderTile(
      BuildContext context, PodcastFolderController fc, PodcastFolder folder) {
    return PodcastCoverTile(
      title: folder.name,
      subtitle: "${folder.podcastIds.length} ${'items'.tr}",
      showPlay: false,
      cover: Container(
        decoration: BoxDecoration(
          color: folder.color.withOpacity(0.22),
          border: Border.all(
            color: folder.color.withOpacity(0.55),
            width: 1.2,
          ),
        ),
        child: Icon(
          Icons.folder_rounded,
          size: 64,
          color: folder.color,
        ),
      ),
      onTap: () => Get.to(() => PodcastFolderScreen(folderId: folder.id)),
      onLongPress: () => _folderOptions(context, fc, folder),
    );
  }

  void _folderOptions(
      BuildContext context, PodcastFolderController fc, PodcastFolder folder) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Obx(() {
          // Refresh color selection when setColor updates the list.
          final current =
              fc.findById(folder.id) ?? folder;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(current.name, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text("folderColor".tr,
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                _FolderColorPicker(
                  selected: current.colorIndex,
                  onChanged: (i) => fc.setColor(current.id, i),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: Text("deleteFolder".tr),
                  onTap: () {
                    fc.deleteFolder(current.id);
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

void _confirmUnfollowRss(BuildContext context, Map<String, dynamic> podcast) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.remove_circle_outline),
          title: Text('${'subscribed'.tr} · ${podcast['title'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('unsubscribe'.tr),
          onTap: () async {
            await PodcastService.unsubscribe('${podcast['feedUrl']}');
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ]),
    ),
  );
}
