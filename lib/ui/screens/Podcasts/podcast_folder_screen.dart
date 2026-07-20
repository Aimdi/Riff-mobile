import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/content_list_widget_item.dart';
import 'podcast_folder_controller.dart';
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
          const itemWidth = 130.0;
          const itemHeight = 180.0;
          final columns =
              (constraints.maxWidth / itemWidth).floor().clamp(2, 6);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 200),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: itemWidth / itemHeight,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => Center(
              child: ContentListItem(
                content: items[index],
                isLibraryItem: true,
              ),
            ),
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
