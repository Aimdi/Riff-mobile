import 'dart:io';

import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';
import 'podcast_folder_controller.dart';

/// A folder's square cover: its photo inside a frame in the folder colour,
/// or (no photo, or the file is gone) the tinted folder icon.
class PodcastFolderCover extends StatelessWidget {
  const PodcastFolderCover({super.key, required this.folder});
  final PodcastFolder folder;

  @override
  Widget build(BuildContext context) {
    final color = folder.color;
    final icon = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withOpacity(RiffPalette.folderTint),
        border: Border.all(
            color: color.withOpacity(RiffPalette.folderEdge), width: 0),
      ),
      child: Center(
        child: Icon(Icons.folder_rounded,
            size: RiffComponentSizes.folderIcon, color: color),
      ),
    );
    final path = folder.imagePath;
    if (path == null) return icon;
    return ColoredBox(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(RiffComponentSizes.folderPhotoFrame),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RiffRadii.xs),
          child: LayoutBuilder(builder: (context, box) {
            final px =
                (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).round();
            return Image.file(
              File(path),
              key: ValueKey(path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: px > 0 ? px : null,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => icon,
            );
          }),
        ),
      ),
    );
  }
}
