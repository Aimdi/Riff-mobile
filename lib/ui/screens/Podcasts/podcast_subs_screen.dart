import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/podcast_service.dart';
import '/services/wizestream_service.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Home/home_layout.dart';
import 'podcast_cover_tile.dart';
import 'podcast_empty_state.dart';
import 'podcast_folder_controller.dart';
import 'podcast_folder_screen.dart';
import 'podcast_layout.dart';
import 'podcasts_library_controller.dart';

/// Long-press a podcast show anywhere it's listed to file it into folders.
/// Reused by the Subscriptions screen and the main Podcasts library grid.
void showPodcastFolderSheet(BuildContext context, Playlist podcast) {
  HapticFeedback.mediumImpact();
  _folderSheet(context, podcast.playlistId, podcast.title, [
    if (WizeStream.isInstalled && WizeStream.showUrlFor(podcast) != null)
      (ctx) => ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text("openInWizeStream".tr),
            onTap: () {
              Navigator.of(ctx).pop();
              WizeStream.open(WizeStream.showUrlFor(podcast)!);
            },
          ),
  ]);
}

/// Long-press a feed (RSS) show: file it into folders, or unfollow it.
void showRssPodcastSheet(BuildContext context, Map<String, dynamic> rss) {
  final feed = '${rss['feedUrl'] ?? ''}';
  if (feed.isEmpty) return;
  HapticFeedback.mediumImpact();
  _folderSheet(context, podcastFolderIdForFeed(feed), '${rss['title'] ?? ''}', [
    (ctx) => ListTile(
          iconColor: Theme.of(ctx).colorScheme.error,
          textColor: Theme.of(ctx).colorScheme.error,
          leading: const Icon(Icons.remove_circle_outline),
          title: Text('unsubscribe'.tr),
          onTap: () async {
            Get.find<PodcastFolderController>()
                .removeEverywhere(podcastFolderIdForFeed(feed));
            await PodcastService.unsubscribe(feed);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
  ]);
}

void _folderSheet(BuildContext context, String id, String title,
    List<Widget Function(BuildContext)> extra) {
  final fc = Get.find<PodcastFolderController>();
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Obx(() => _sheetRows(
          ctx,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    left: RiffSpacing.lg,
                    top: RiffSpacing.lg,
                    right: RiffSpacing.lg,
                    bottom: RiffSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${'addToFolder'.tr} · $title",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              if (fc.folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RiffSpacing.lg, vertical: RiffSpacing.xs),
                  child: Text('noFoldersYet'.tr,
                      style: Theme.of(ctx).textTheme.bodySmall),
                ),
              ...fc.folders.map((f) => CheckboxListTile(
                    value: fc.contains(f.id, id),
                    onChanged: (_) => fc.toggle(f.id, id),
                    title: Text(f.name),
                    secondary: Icon(Icons.folder_rounded, color: f.color),
                  )),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text("newFolder".tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showNewPodcastFolderDialog(context, assignPodcastId: id);
                },
              ),
              for (final b in extra) b(ctx),
            ],
          ))),
    ),
  );
}

/// Sheet rows per RIFF_UI_RESTYLE.md §5.10: 15/400 labels and 22 dp icons
/// in the primary text colour.
Widget _sheetRows(BuildContext ctx, Widget child) => ListTileTheme.merge(
      titleTextStyle: Theme.of(ctx).textTheme.bodyLarge,
      iconColor: Theme.of(ctx).colorScheme.onSurface,
      child: IconTheme.merge(
        data: const IconThemeData(size: RiffComponentSizes.headerIcon),
        child: child,
      ),
    );

/// Drag folders into the order they show in Subscriptions.
void showReorderFoldersSheet(BuildContext context) {
  final fc = Get.find<PodcastFolderController>();
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.lg,
                  top: RiffSpacing.lg,
                  right: RiffSpacing.lg,
                  bottom: RiffSpacing.sm),
              child: Text('reorderFolders'.tr,
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Flexible(
              child: Obx(() => ReorderableListView.builder(
                    shrinkWrap: true,
                    itemCount: fc.folders.length,
                    onReorder: fc.move,
                    itemBuilder: (_, i) {
                      final f = fc.folders[i];
                      return ListTile(
                        key: ValueKey(f.id),
                        leading: Icon(Icons.folder_rounded, color: f.color),
                        title: Text(f.name),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle_rounded),
                        ),
                      );
                    },
                  )),
            ),
          ],
        ),
      ),
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
                  isDense: true,
                ),
              ),
              const SizedBox(height: RiffSpacing.md),
              Text("folderColor".tr, style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: RiffSpacing.sm),
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
      spacing: RiffSpacing.sm,
      runSpacing: RiffSpacing.sm,
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
                  ? Icon(Icons.check,
                      size: 16, color: RiffColors.of(context).onImage)
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
          gridDelegate: podcastSubsGridDelegate(constraints.maxWidth,
              textScaler: MediaQuery.textScalerOf(context)),
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
                    ? youtubeChannelBadge(context)
                    : null,
                onTap: () => openLibraryPodcast(podcast),
                onPlay: () => playLibraryPodcast(podcast),
                onLongPress: () => showPodcastFolderSheet(context, podcast),
              );
            }
            final rss = rssSubs[subIndex - subs.length];
            return PodcastCoverTile(
              title: (rss['title'] ?? '').toString(),
              subtitle: (rss['author'] ?? '').toString(),
              imageUrl: rssArtworkUrl(rss),
              onTap: () => playOrOpenRssPodcast(rss),
              onPlay: () => playOrOpenRssPodcast(rss),
              onLongPress: () => showRssPodcastSheet(context, rss),
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
            final shows = controller.libraryPodcasts.length +
                PodcastService.subscriptions.length;
            return Padding(
              padding: const EdgeInsets.only(
                  left: HomeLayout.gutter,
                  top: RiffSpacing.sm,
                  right: RiffSpacing.xs,
                  bottom: RiffSpacing.xxs),
              child: SizedBox(
                height: RiffComponentSizes.iconHit,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        podcastShowCount(shows),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: homeMutedColor(context)),
                      ),
                    ),
                    if (folders.folders.length > 1)
                      IconButton(
                        tooltip: 'reorderFolders'.tr,
                        icon: const Icon(Icons.swap_vert_rounded,
                            size: RiffComponentSizes.headerIcon),
                        onPressed: () => showReorderFoldersSheet(context),
                      ),
                    // Accent text button from the theme (§5.5).
                    TextButton.icon(
                      onPressed: () => showNewPodcastFolderDialog(context),
                      icon: const Icon(Icons.create_new_folder_outlined,
                          size: RiffComponentSizes.trailingIcon),
                      label: Text("newFolder".tr),
                    ),
                  ],
                ),
              ),
            );
          }),
          Expanded(child: content),
        ],
      );
    }
    return Scaffold(
      body: Column(children: [
        RiffPageHeader("subscriptions".tr, actions: [
          Obx(() => folders.folders.length > 1
              ? IconButton(
                  tooltip: 'reorderFolders'.tr,
                  icon: const Icon(Icons.swap_vert_rounded),
                  onPressed: () => showReorderFoldersSheet(context),
                )
              : const SizedBox.shrink()),
          IconButton(
            tooltip: "newFolder".tr,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => showNewPodcastFolderDialog(context),
          ),
        ]),
        Expanded(child: content),
      ]),
    );
  }

  Widget _folderTile(
      BuildContext context, PodcastFolderController fc, PodcastFolder folder) {
    return PodcastCoverTile(
      title: folder.name,
      subtitle: podcastShowCount(folder.podcastIds.length),
      showPlay: false,
      cover: Container(
        decoration: BoxDecoration(
          color: folder.color.withOpacity(0.22),
          border: Border.all(
            color: folder.color.withOpacity(0.55),
            width: 0,
          ),
        ),
        child: Icon(
          Icons.folder_rounded,
          size: RiffComponentSizes.folderIcon,
          color: folder.color,
        ),
      ),
      onTap: () => Get.to(() => PodcastFolderScreen(folderId: folder.id)),
      onLongPress: () => _folderOptions(context, fc, folder),
    );
  }

  void _folderOptions(
      BuildContext context, PodcastFolderController fc, PodcastFolder folder) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Obx(() {
          // Refresh color selection when setColor updates the list.
          final current = fc.findById(folder.id) ?? folder;
          return Padding(
            padding: const EdgeInsets.only(
                left: RiffSpacing.lg,
                top: RiffSpacing.sm,
                right: RiffSpacing.lg,
                bottom: RiffSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(current.name, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: RiffSpacing.md),
                Text("folderColor".tr,
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: RiffSpacing.sm),
                _FolderColorPicker(
                  selected: current.colorIndex,
                  onChanged: (i) => fc.setColor(current.id, i),
                ),
                const SizedBox(height: RiffSpacing.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  iconColor: Theme.of(ctx).colorScheme.error,
                  textColor: Theme.of(ctx).colorScheme.error,
                  titleTextStyle: Theme.of(ctx).textTheme.bodyLarge,
                  leading: const Icon(Icons.delete_outline,
                      size: RiffComponentSizes.headerIcon),
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
