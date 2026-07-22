import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/podcast_service.dart';
import '/ui/widgets/content_list_widget_item.dart';
import 'podcast_folder_controller.dart';
import 'podcast_folder_screen.dart';
import 'podcasts_library_controller.dart';
import 'podcasts_screen.dart';

/// Shared tile footprint so folders, library shows, and RSS subs line up
/// in the Subs grid (matches [ContentListItem]: 130×180 with a 120 cover).
const double _subsTileWidth = 130;
const double _subsTileHeight = 180;
const double _subsCoverSize = 120;
const EdgeInsets _subsTilePadding =
    EdgeInsets.symmetric(horizontal: 5);

/// Long-press a podcast show anywhere it's listed to file it into folders.
/// Reused by the Subscriptions screen and the main Podcasts library grid.
void showPodcastFolderSheet(BuildContext context, Playlist podcast) {
  final fc = Get.find<PodcastFolderController>();
  showModalBottomSheet(
    context: context,
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

/// Subscriptions ("Abonnements"): a grid of every podcast you follow, with
/// Spotify-style folders. Folder tiles come first; long-press a show to file
/// it into a folder, long-press a folder to delete it.
class PodcastSubsScreen extends StatelessWidget {
  const PodcastSubsScreen({super.key, this.embedded = false});

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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "noPodcastsBookmarked".tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        return LayoutBuilder(builder: (context, constraints) {
          final columns =
              (constraints.maxWidth / _subsTileWidth).floor().clamp(2, 6);
          final total = folderList.length + subs.length + rssSubs.length;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 200),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: _subsTileWidth / _subsTileHeight,
            ),
            itemCount: total,
            itemBuilder: (context, index) {
              if (index < folderList.length) {
                return Center(
                    child: _folderTile(context, folders, folderList[index]));
              }
              final subIndex = index - folderList.length;
              if (subIndex < subs.length) {
                final podcast = subs[subIndex];
                return Center(
                  child: GestureDetector(
                    onLongPress: () => showPodcastFolderSheet(context, podcast),
                    child: ContentListItem(
                      content: podcast,
                      isLibraryItem: true,
                    ),
                  ),
                );
              }
              final rss = rssSubs[subIndex - subs.length];
              return Center(child: _RssSubTile(podcast: rss));
            },
          );
        });
    });
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showNewPodcastFolderDialog(context),
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              label: Text("newFolder".tr),
            ),
          ),
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
    final theme = Theme.of(context);
    return SizedBox(
      width: _subsTileWidth,
      height: _subsTileHeight,
      child: Padding(
        padding: _subsTilePadding,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Get.to(() => PodcastFolderScreen(folderId: folder.id)),
          onLongPress: () => _folderOptions(context, fc, folder),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: _subsCoverSize,
                child: Container(
                  decoration: BoxDecoration(
                    color: folder.color.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: folder.color.withOpacity(0.55),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    size: 48,
                    color: folder.color,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      "${folder.podcastIds.length} ${'items'.tr}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _folderOptions(
      BuildContext context, PodcastFolderController fc, PodcastFolder folder) {
    showModalBottomSheet(
      context: context,
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

/// Tile for an iTunes/RSS subscription in the Subs grid. Tapping opens the
/// episode list; long-press offers to unfollow.
class _RssSubTile extends StatelessWidget {
  const _RssSubTile({required this.podcast});
  final Map<String, dynamic> podcast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final art = Thumbnail((podcast['artwork'] ?? '').toString()).high;
    return SizedBox(
      width: _subsTileWidth,
      height: _subsTileHeight,
      child: Padding(
        padding: _subsTilePadding,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Get.to(() => PodcastEpisodesScreen(podcast: podcast)),
          onLongPress: () => _confirmUnfollow(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: art,
                  width: _subsCoverSize,
                  height: _subsCoverSize,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: _subsCoverSize,
                    height: _subsCoverSize,
                    color: theme.colorScheme.secondary.withOpacity(0.3),
                    child: const Icon(Icons.podcasts, size: 44),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: Text(
                  (podcast['title'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmUnfollow(BuildContext context) {
    showModalBottomSheet(
      context: context,
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
}
