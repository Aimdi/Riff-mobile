import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import 'podcast_cover_tile.dart';
import 'podcast_folder_controller.dart';
import 'podcast_subs_screen.dart';
import 'podcasts_library_controller.dart';

/// The shows inside one podcast folder.
class PodcastFolderScreen extends StatelessWidget {
  const PodcastFolderScreen({super.key, required this.folderId});
  final String folderId;

  @override
  Widget build(BuildContext context) {
    final fc = Get.find<PodcastFolderController>();
    final lib = Get.find<LibraryPodcastsController>();
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(fc.findById(folderId)?.name ?? "folder".tr)),
        actions: [
          IconButton(
            tooltip: "rename".tr,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(context, fc),
          ),
          IconButton(
            tooltip: "deleteFolder".tr,
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              fc.deleteFolder(folderId);
              Get.back();
            },
          ),
        ],
      ),
      body: Obx(() {
        final folder = fc.findById(folderId);
        if (folder == null) {
          return const SizedBox.shrink();
        }
        final ids = folder.podcastIds.toSet();
        final items = lib.libraryPodcasts
            .where((p) => ids.contains(p.playlistId))
            .toList();
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "folderEmpty".tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        return LayoutBuilder(builder: (context, constraints) {
          return GridView.builder(
            padding: kPodcastSubsGridPadding,
            gridDelegate: podcastSubsGridDelegate(constraints.maxWidth),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final podcast = items[index];
              return PodcastCoverTile(
                title: podcast.title,
                subtitle: libraryPodcastSubtitle(podcast),
                imageUrl: Thumbnail(podcast.thumbnailUrl).high,
                badge: isYoutubeChannelPodcast(podcast)
                    ? youtubeChannelBadge()
                    : null,
                onTap: () => playLibraryPodcast(podcast),
                onPlay: () => playLibraryPodcast(podcast),
                onLongPress: () => showPodcastFolderSheet(context, podcast),
              );
            },
          );
        });
      }),
    );
  }

  void _rename(BuildContext context, PodcastFolderController fc) {
    final ctrl =
        TextEditingController(text: fc.findById(folderId)?.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("rename".tr),
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
              if (ctrl.text.trim().isNotEmpty) {
                fc.rename(folderId, ctrl.text);
              }
              Navigator.of(ctx).pop();
            },
            child: Text("save".tr),
          ),
        ],
      ),
    );
  }
}
