import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../navigator.dart';
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';
import 'image_widget.dart';

class ContentListItem extends StatelessWidget {
  const ContentListItem(
      {super.key,
      required this.content,
      this.isLibraryItem = false,
      this.showSimilarOnOpen = false});

  ///content will be of Type class Album or Playlist
  final dynamic content;
  final bool isLibraryItem;

  /// When true (podcast search results), the opened playlist shows a pinned
  /// "Similar podcasts" section at the bottom.
  final bool showSimilarOnOpen;

  String _subtitle(bool isAlbum) {
    if (isAlbum) {
      final artists = content.artists as List?;
      final artistName = (artists != null && artists.isNotEmpty)
          ? (artists[0]['name']?.toString() ?? '')
          : '';
      final year = content.year?.toString() ?? '';
      return [artistName, year]
          .where((s) => s.isNotEmpty)
          .join(' • ');
    }
    if (isLibraryItem) {
      final count = content.songCount?.toString();
      if (count != null && count.isNotEmpty && count != 'null') {
        return '$count ${"songs".tr}';
      }
      final desc = content.description?.toString() ?? '';
      if (desc.isNotEmpty && desc != 'Playlist') return desc;
      return '';
    }
    return content.description?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final isAlbum = content.runtimeType.toString() == "Album";
    final muted = Theme.of(context).brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.6);
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () {
        if (isAlbum) {
          Get.toNamed(ScreenNavigationSetup.albumScreen,
              id: ScreenNavigationSetup.id,
              arguments: (content, content.browseId));
          return;
        }
        Get.toNamed(ScreenNavigationSetup.playlistScreen,
            id: ScreenNavigationSetup.id,
            arguments: [content, content.playlistId, showSimilarOnOpen]);
      },
      child: SizedBox(
        width: 112,
        height: 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isAlbum
                ? ImageWidget(
                    size: 112,
                    album: content,
                    borderRadius: RiffTokens.radiusSm,
                  )
                : content.isCloudPlaylist ||
                        !(content.playlistId == 'LIBRP' ||
                            content.playlistId == 'LIBFAV' ||
                            content.playlistId == 'SongsCache' ||
                            content.playlistId == 'SongDownloads')
                    ? ImageWidget(
                        size: 112,
                        playlist: content,
                        borderRadius: RiffTokens.radiusSm,
                      )
                    : Container(
                        height: 112,
                        width: 112,
                        decoration: BoxDecoration(
                            color: Theme.of(context).primaryColorLight,
                            borderRadius:
                                BorderRadius.circular(RiffTokens.radiusSm)),
                        child: Center(
                            child: Icon(
                          content.playlistId == 'LIBRP'
                              ? Icons.history
                              : content.playlistId == 'LIBFAV'
                                  ? Icons.favorite
                                  : content.playlistId == 'SongsCache'
                                      ? Icons.flight
                                      : Icons.download,
                          color: Colors.white,
                          size: 36,
                        ))),
            const SizedBox(height: 8),
            Text(
              content.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: -0.15,
                    height: 1.15,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              _subtitle(isAlbum),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: muted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
