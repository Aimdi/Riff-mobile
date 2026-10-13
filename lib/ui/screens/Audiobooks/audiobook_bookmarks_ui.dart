import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/media_item_extras.dart';
import '/services/audiobook_bookmarks.dart';
import '/services/audiobook_progress_service.dart';
import '/services/podcast_segments.dart' show formatSegmentLength;
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_sheet.dart';
import '/ui/widgets/snackbar.dart';
import '../Home/home_layout.dart';

String _at(int ms) => formatSegmentLength(ms / 1000);

/// The book the player is reading from, if it's an audiobook.
String? _playingBook(PlayerController pc) {
  final song = pc.currentSong.value;
  return song == null || !song.isAudiobook
      ? null
      : AudiobookProgressService.bookIdOf(song);
}

/// Bookmark the moment playing in the book (Audible's bookmarks).
Future<void> bookmarkBookMoment(BuildContext context) async {
  final pc = Get.find<PlayerController>();
  final track = pc.currentSong.value;
  if (track == null || !track.isAudiobook) return;
  HapticFeedback.mediumImpact();
  final target = undoSnackbarTarget(context);
  final bm = await AudiobookBookmarkStore.add(
      track, pc.progressBarStatus.value.current,
      trackIndex: pc.currentQueue.indexWhere((m) => m.id == track.id));
  if (bm == null) return;
  showUndoSnackbar(
      target, 'bookmarkSaved'.trParams({'time': _at(bm.positionMs)}));
}

/// Play from [bm]: its track is in the queue while its book plays.
void openAudiobookBookmark(BuildContext context, AudiobookBookmark bm) {
  final pc = Get.find<PlayerController>();
  final index = pc.currentQueue.indexWhere((m) => m.id == bm.trackId);
  if (index < 0) {
    showUndoSnackbar(undoSnackbarTarget(context), 'bookmarkCantPlayBook'.tr);
    return;
  }
  pc.playQueueItemAt(index, Duration(milliseconds: bm.positionMs));
}

/// "Bookmark this moment" and "Bookmarks in this book" as rows of the
/// audiobook player's ⋮ sheet; nothing for anything but a book.
class AudiobookBookmarkTiles extends StatelessWidget {
  const AudiobookBookmarkTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    return Obx(() {
      AudiobookBookmarkStore.rev.value;
      final book = _playingBook(pc);
      if (book == null) return const SizedBox.shrink();
      final count = AudiobookBookmarkStore.forBook(book).length;

      /// Closes this sheet; the next one opens from the player's scaffold.
      BuildContext closeSheet() {
        final host = pc.homeScaffoldkey.currentContext ?? context;
        Navigator.of(context).pop();
        return host;
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RiffSheetDivider(),
          RiffSheetTile(
            icon: Icons.bookmark_add_outlined,
            title: 'bookmarkThisMoment'.tr,
            onTap: () => bookmarkBookMoment(closeSheet()),
          ),
          RiffSheetTile(
            icon: Icons.bookmarks_outlined,
            title: 'bookBookmarks'.tr,
            trailing: count > 0 ? Text('$count') : null,
            onTap: () => showBookBookmarksSheet(closeSheet()),
          ),
        ],
      );
    });
  }
}

/// The playing book's bookmarks, in reading order: tap one to play from
/// there, remove one with Undo.
Future<void> showBookBookmarksSheet(BuildContext context) {
  final pc = Get.find<PlayerController>();
  final book = _playingBook(pc);
  if (book == null) return Future.value();
  return showModalBottomSheet<void>(
    context: pc.homeScaffoldkey.currentContext ?? context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * 0.7,
      // Own messenger so the snackbars show above the sheet.
      child: ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Builder(
            builder: (inner) => Obx(() {
              AudiobookBookmarkStore.rev.value;
              final list = AudiobookBookmarkStore.forBook(book);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const RiffSheetHandle(),
                  RiffSheetTitle('bookBookmarks'.tr,
                      subtitle: pc.currentSong.value?.album),
                  RiffSheetTile(
                    icon: Icons.bookmark_add_outlined,
                    title: 'bookmarkThisMoment'.tr,
                    subtitle:
                        _at(pc.progressBarStatus.value.current.inMilliseconds),
                    onTap: () => bookmarkBookMoment(inner),
                  ),
                  const RiffSheetDivider(),
                  Expanded(
                    child: list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(RiffSpacing.xxl),
                            child: Text('noBookBookmarks'.tr,
                                textAlign: TextAlign.center,
                                style: homeCardSubtitleStyle(inner)),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.only(bottom: RiffSpacing.xxl),
                            itemCount: list.length,
                            itemBuilder: (_, i) => AudiobookBookmarkTile(
                              bookmark: list[i],
                              onTap: () {
                                Navigator.of(sheet).pop();
                                openAudiobookBookmark(context, list[i]);
                              },
                            ),
                          ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    ),
  );
}

/// One bookmark: the time in a tag, the chapter, and Remove.
class AudiobookBookmarkTile extends StatelessWidget {
  const AudiobookBookmarkTile(
      {super.key, required this.bookmark, required this.onTap});
  final AudiobookBookmark bookmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final title = bookmark.trackTitle.isEmpty
        ? 'bookChapter'.trParams({'n': '${bookmark.trackIndex + 1}'})
        : bookmark.trackTitle;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(
            left: RiffSpacing.lg,
            top: RiffSpacing.sm,
            right: RiffSpacing.xs,
            bottom: RiffSpacing.sm),
        child: Row(
          children: [
            // Timestamp tag: surface2, not accent (§2.5).
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: RiffSpacing.sm, vertical: RiffSpacing.xxs),
              decoration: BoxDecoration(
                color: RiffColors.of(context).surface2,
                borderRadius: BorderRadius.circular(RiffRadii.xs),
              ),
              child: Text(_at(bookmark.positionMs),
                  style: theme.textTheme.labelSmall?.copyWith(color: fg)),
            ),
            const SizedBox(width: RiffSpacing.md),
            Expanded(
              child: Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
            ),
            IconButton(
              tooltip: 'bookmarkRemove'.tr,
              icon: const Icon(Icons.close_rounded,
                  size: RiffComponentSizes.trailingIcon),
              onPressed: () {
                final target = undoSnackbarTarget(context);
                AudiobookBookmarkStore.remove(bookmark.id);
                showUndoSnackbar(target, 'bookmarkRemoved'.tr,
                    onUndo: () => AudiobookBookmarkStore.restore(bookmark));
              },
            ),
          ],
        ),
      ),
    );
  }
}
