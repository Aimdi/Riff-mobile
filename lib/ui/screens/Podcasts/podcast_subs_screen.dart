import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/ui/widgets/content_list_widget_item.dart';
import 'podcast_folder_controller.dart';
import 'podcast_folder_screen.dart';
import 'podcasts_library_controller.dart';

/// Subscriptions ("Abonnements"): a grid of every podcast you follow, with
/// Spotify-style folders. Folder tiles come first; long-press a show to file
/// it into a folder, long-press a folder to rename/delete it.
class PodcastSubsScreen extends StatelessWidget {
  const PodcastSubsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LibraryPodcastsController>();
    final folders = Get.find<PodcastFolderController>();
    return Scaffold(
      appBar: AppBar(
        title: Text("subscriptions".tr),
        actions: [
          IconButton(
            tooltip: "newFolder".tr,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _newFolder(context, folders),
          ),
        ],
      ),
      body: Obx(() {
        final subs = controller.libraryPodcasts.toList();
        final folderList = folders.folders.toList();
        if (subs.isEmpty && folderList.isEmpty) {
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
          const itemWidth = 130.0;
          const itemHeight = 180.0;
          final columns =
              (constraints.maxWidth / itemWidth).floor().clamp(2, 6);
          final total = folderList.length + subs.length;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 200),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: itemWidth / itemHeight,
            ),
            itemCount: total,
            itemBuilder: (context, index) {
              // Folder tiles first, then the podcast shows.
              if (index < folderList.length) {
                return Center(
                    child: _folderTile(context, folders, folderList[index]));
              }
              final podcast = subs[index - folderList.length];
              return Center(
                child: GestureDetector(
                  onLongPress: () =>
                      _assignSheet(context, folders, podcast),
                  child: ContentListItem(
                    content: podcast,
                    isLibraryItem: true,
                  ),
                ),
              );
            },
          );
        });
      }),
    );
  }

  Widget _folderTile(
      BuildContext context, PodcastFolderController fc, PodcastFolder folder) {
    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Get.to(() => PodcastFolderScreen(folderId: folder.id)),
        onLongPress: () => _folderOptions(context, fc, folder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.folder_rounded,
                size: 56,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              "${folder.podcastIds.length} ${'items'.tr}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _newFolder(BuildContext context, PodcastFolderController fc,
      {String? assignPodcastId}) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("newFolder".tr),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: "folderName".tr,
            border: const OutlineInputBorder(),
            isDense: true,
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
                final f = fc.createFolder(name);
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
    );
  }

  /// Long-press a show: pick which folders it belongs to.
  void _assignSheet(
      BuildContext context, PodcastFolderController fc, Playlist podcast) {
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
                ...fc.folders.map((f) => CheckboxListTile(
                      value: fc.contains(f.id, podcast.playlistId),
                      onChanged: (_) => fc.toggle(f.id, podcast.playlistId),
                      title: Text(f.name),
                      secondary: const Icon(Icons.folder_rounded),
                    )),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: Text("newFolder".tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _newFolder(context, fc,
                        assignPodcastId: podcast.playlistId);
                  },
                ),
              ],
            )),
      ),
    );
  }

  void _folderOptions(
      BuildContext context, PodcastFolderController fc, PodcastFolder folder) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text("deleteFolder".tr),
            onTap: () {
              fc.deleteFolder(folder.id);
              Navigator.of(ctx).pop();
            },
          ),
        ]),
      ),
    );
  }
}
