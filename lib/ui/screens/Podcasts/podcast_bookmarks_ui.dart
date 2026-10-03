import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '/models/thumbnail.dart';
import '/services/podcast_bookmarks.dart';
import '/services/podcast_segments.dart' show formatSegmentLength;
import '/ui/player/player_controller.dart';
import '../../widgets/common_dialog_widget.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/snackbar.dart';
import '../Home/home_layout.dart';
import 'podcast_empty_state.dart';

String _at(int ms) => formatSegmentLength(ms / 1000);

/// Bookmark the current moment of the playing episode (no quote), from the
/// podcast player's menu. Works with or without a transcript.
Future<void> bookmarkCurrentMoment(BuildContext context) async {
  final pc = Get.find<PlayerController>();
  final item = pc.currentSong.value;
  if (item == null || !pc.isCurrentSongPodcast) return;
  HapticFeedback.mediumImpact();
  final bm = await PodcastBookmarkStore.add(
      item, pc.progressBarStatus.value.current);
  if (bm == null || !context.mounted) return;
  showBookmarkSavedSnack(context, bm);
}

/// "Bookmarked at 12:34" with an Add note action.
void showBookmarkSavedSnack(BuildContext context, PodcastBookmark bm) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('bookmarkSaved'.trParams({'time': _at(bm.positionMs)})),
      action: SnackBarAction(
        label: 'bookmarkAddNote'.tr,
        onPressed: () => editBookmarkNote(context, bm),
      ),
    ));
}

Future<void> editBookmarkNote(BuildContext context, PodcastBookmark bm) async {
  final ctrl = TextEditingController(text: bm.note ?? '');
  final saved = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (d) => CommonDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RiffDialogTitle(
                bm.note == null ? 'bookmarkAddNote'.tr : 'bookmarkEditNote'.tr,
                icon: Icons.edit_note_rounded,
                subtitle: bm.quote.isEmpty ? null : '“${bm.quote}”'),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'bookmarkNoteHint'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            RiffDialogButton('save'.tr,
                onPressed: () => Navigator.of(d).pop(true)),
            RiffDialogButton('cancel'.tr,
                primary: false, onPressed: () => Navigator.of(d).pop(false)),
          ],
        ),
      ),
    ),
  );
  if (saved == true) await PodcastBookmarkStore.setNote(bm, ctrl.text);
  ctrl.dispose();
}

Future<void> _removeWithUndo(BuildContext context, PodcastBookmark bm) async {
  await PodcastBookmarkStore.remove(bm.id);
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('bookmarkRemoved'.tr),
      action: SnackBarAction(
          label: 'undo'.tr,
          onPressed: () => PodcastBookmarkStore.restore(bm)),
    ));
}

/// Play the bookmark's episode from its moment (or seek, if it's playing).
Future<void> playBookmark(BuildContext context, PodcastBookmark bm) async {
  final item = mediaItemFromSnapshot(bm.episode);
  if (item == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        snackbar(context, 'bookmarkCantPlay'.tr, size: SanckBarSize.MEDIUM));
    return;
  }
  await Get.find<PlayerController>().playPodcastAt(
      item, Duration(milliseconds: bm.positionMs),
      from: bm.showTitle);
}

/// One bookmark: the moment, the quote, the note, and its actions.
class PodcastBookmarkTile extends StatelessWidget {
  const PodcastBookmarkTile(
      {super.key, required this.bookmark, this.showEpisode = true, this.onTap});
  final PodcastBookmark bookmark;
  final bool showEpisode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = bookmark;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final fg = theme.textTheme.titleMedium?.color;
    final art = Thumbnail('${b.episode['artUri'] ?? ''}').medium;
    return InkWell(
      onTap: onTap ?? () => playBookmark(context, b),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(HomeLayout.gutter, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showEpisode)
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: art.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: art,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Icon(Icons.podcasts_rounded, color: accent),
                          )
                        : Icon(Icons.podcasts_rounded, color: accent),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_at(b.positionMs),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accent,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                      if (showEpisode) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            [b.showTitle, b.episodeTitle]
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: homeCardSubtitleStyle(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (b.quote.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('“${b.quote}”',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            height: 1.35,
                            fontStyle: FontStyle.italic,
                            color: fg)),
                  ],
                  if (b.note != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sticky_note_2_outlined,
                            size: 15, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(b.note!,
                              style: homeCardSubtitleStyle(context)
                                  .copyWith(fontSize: 13.5)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<int>(
              tooltip: 'moreOptions'.tr,
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (v) {
                switch (v) {
                  case 0:
                    Share.share(formatBookmarkShare(b));
                  case 1:
                    editBookmarkNote(context, b);
                  case 2:
                    _removeWithUndo(context, b);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 0, child: Text('share'.tr)),
                PopupMenuItem(
                    value: 1,
                    child: Text(b.note == null
                        ? 'bookmarkAddNote'.tr
                        : 'bookmarkEditNote'.tr)),
                PopupMenuItem(value: 2, child: Text('bookmarkRemove'.tr)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// This episode's bookmarks, from the podcast player. Tapping one jumps
/// there.
Future<void> showEpisodeBookmarksSheet(BuildContext context) {
  final pc = Get.find<PlayerController>();
  final item = pc.currentSong.value;
  if (item == null) return Future.value();
  return showModalBottomSheet<void>(
    context: pc.homeScaffoldkey.currentContext ?? context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: riffSheetShape,
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * 0.7,
      // Own messenger so Undo / Add note snacks show above the sheet.
      child: ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Builder(
            builder: (inner) => Obx(() {
              PodcastBookmarkStore.rev.value;
              final list = PodcastBookmarkStore.forEpisode(item.id);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const RiffSheetHandle(),
                  RiffSheetTitle('episodeBookmarks'.tr, subtitle: item.title),
                  RiffSheetTile(
                    icon: Icons.bookmark_add_outlined,
                    title: 'bookmarkThisMoment'.tr,
                    subtitle: _at(pc.progressBarStatus.value.current
                        .inMilliseconds),
                    onTap: () => bookmarkCurrentMoment(inner),
                  ),
                  const RiffSheetDivider(),
                  Expanded(
                    child: list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('noEpisodeBookmarks'.tr,
                                textAlign: TextAlign.center,
                                style: homeCardSubtitleStyle(inner)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: list.length,
                            itemBuilder: (_, i) => PodcastBookmarkTile(
                              bookmark: list[i],
                              showEpisode: false,
                              onTap: () {
                                Navigator.of(sheet).pop();
                                pc.seek(Duration(
                                    milliseconds: list[i].positionMs));
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

/// Every bookmark, newest first: the Bookmarks tab in Podcasts.
class PodcastBookmarksScreen extends StatelessWidget {
  const PodcastBookmarksScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = Obx(() {
      PodcastBookmarkStore.rev.value;
      final list = PodcastBookmarkStore.all;
      if (list.isEmpty) {
        return PodcastEmptyState(
          icon: Icons.bookmarks_outlined,
          message: 'noPodcastBookmarks'.tr,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 200),
        itemCount: list.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) => PodcastBookmarkTile(bookmark: list[i]),
      );
    });
    if (embedded) return body;
    return Scaffold(
      body: Column(children: [
        RiffPageHeader('bookmarks'.tr),
        Expanded(child: body),
      ]),
    );
  }
}
