import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/screens/Library/library_pins.dart';
import '../navigator.dart';
import '../player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';
import 'collection_play.dart';
import 'generated_cover.dart';
import 'image_widget.dart';
import 'podcast_play.dart';
import 'riff_motion.dart';
import '/services/search_recents.dart';
import '../screens/Library/playlist_folder_ui.dart' show showMoveToFolderSheet;
import 'snackbar.dart';
import 'song_list_tile.dart' show RiffRowHairline;
import '../screens/Home/home_layout.dart' show HomeLayout;

class ContentListItem extends StatelessWidget {
  const ContentListItem(
      {super.key,
      required this.content,
      this.isLibraryItem = false,
      this.showSimilarOnOpen = false,
      this.size = defaultSize,
      this.asRow = false});

  /// A row of a list (Library's list view): the cover at [size], then the
  /// title and subtitle, opening and long-pressing as the card does.
  final bool asRow;

  /// Cover width of a shelf card; grids pass a size that fills a column.
  static const double defaultSize = 112;
  final double size;

  /// The play button over the cover's bottom-right corner: its offset from
  /// the edges, its padding and glyph (keep the current sizes), and how
  /// far in from the right edge it reaches.
  static const double _playInset = RiffSpacing.xs;
  static const double _playPadding = RiffSpacing.xxs;
  static const double _playGlyph = 26;
  static const double _playReach = _playInset + 2 * _playPadding + _playGlyph;

  /// Height of a card of [size]: cover, gap, one-line title and subtitle,
  /// grown with the system text size.
  static double heightFor(BuildContext context, double size) {
    final scaler = MediaQuery.textScalerOf(context);
    final text = Theme.of(context).textTheme;
    // Line boxes of the title (labelMedium) and subtitle (bodySmall) slots.
    double line(TextStyle? style) {
      final size = style?.fontSize ?? 14;
      return scaler.scale(size) * (style?.height ?? 1.2);
    }

    return size + 8 + line(text.labelMedium) + 2 + line(text.bodySmall) + 2;
  }

  /// Built-in library playlists store their title as a translation key
  /// (the list is built before translations load), so show the real name.
  String get _title {
    final title = content.title?.toString() ?? '';
    if (!_isAlbum && isSystemLibraryPlaylistId('${content.playlistId}')) {
      return title.tr;
    }
    return title;
  }

  ///content will be of Type class Album or Playlist
  final dynamic content;
  final bool isLibraryItem;

  /// When true (podcast search results), the opened playlist shows a pinned
  /// "Similar podcasts" section at the bottom.
  final bool showSimilarOnOpen;

  bool get _isAlbum => content is Album;

  String _subtitle(bool isAlbum) {
    if (isAlbum) {
      final artists = content.artists as List?;
      final artistName = (artists != null && artists.isNotEmpty)
          ? (artists[0]['name']?.toString() ?? '')
          : '';
      final year = content.year?.toString() ?? '';
      return [artistName, year].where((s) => s.isNotEmpty).join(' • ');
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

  void _openContent() {
    if (_isAlbum) {
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id, arguments: (content, content.browseId));
      return;
    }
    Get.toNamed(ScreenNavigationSetup.playlistScreen,
        id: ScreenNavigationSetup.id,
        arguments: [content, content.playlistId, showSimilarOnOpen]);
  }

  String get _collectionId => _isAlbum
      ? (content.browseId?.toString() ?? '')
      : (content.playlistId?.toString() ?? '');

  String? get _collectionKind => _isAlbum ? null : content.kind?.toString();

  /// Play without opening the screen when tracks are a one-liner fetch.
  /// Falls back to opening the album/playlist if that path is empty or throws.
  Future<void> _playFromOverlay({bool shuffle = false}) async {
    try {
      if (!_isAlbum &&
          isPodcastCollection(kind: _collectionKind, id: _collectionId)) {
        final tracks = await loadCollectionPlayTracks(
          isAlbum: false,
          id: _collectionId,
          isLibraryItem: isLibraryItem,
          isPipedPlaylist: content.isPipedPlaylist == true,
          isCloudPlaylist: content.isCloudPlaylist != false,
        );
        if (tracks.isNotEmpty) {
          final ok = await playCollectionTracksAsPodcast(
            tracks: tracks,
            title: _title,
            shuffle: shuffle,
          );
          if (ok) return;
        }
      }
      final ok = await playCollection(
        isAlbum: _isAlbum,
        id: _collectionId,
        title: _title,
        shuffle: shuffle,
        isLibraryItem: isLibraryItem,
        isPipedPlaylist: !_isAlbum && content.isPipedPlaylist == true,
        isCloudPlaylist: _isAlbum || content.isCloudPlaylist != false,
      );
      if (!ok) {
        _snackOperationFailed();
        _openContent();
      }
    } catch (_) {
      _snackOperationFailed();
      _openContent();
    }
  }

  void _snackOperationFailed() => snackOperationFailed();

  Future<void> _queueFromSheet({required bool radio}) async {
    final tracks = await loadCollectionPlayTracks(
      isAlbum: _isAlbum,
      id: _collectionId,
      isLibraryItem: isLibraryItem,
      isPipedPlaylist: !_isAlbum && content.isPipedPlaylist == true,
      isCloudPlaylist: _isAlbum || content.isCloudPlaylist != false,
    );
    if (tracks.isEmpty || !Get.isRegistered<PlayerController>()) {
      _snackOperationFailed();
      return;
    }
    final player = Get.find<PlayerController>();
    if (radio) {
      final ok = await player.startRadio(tracks.first);
      if (!ok) _snackOperationFailed();
      return;
    }
    final queued = await player.playNextList(tracks);
    if (!queued) _snackOperationFailed();
  }

  /// Library playlists, all but Riff's own four, can be pinned to the top.
  bool get _canPin =>
      isLibraryItem &&
      !_isAlbum &&
      !isSystemLibraryPlaylistId(_collectionId) &&
      Get.isRegistered<LibraryPlaylistsController>();

  Future<void> _togglePin(UndoSnackbarTarget? target) async {
    final pinning = !LibraryPins.isPinned(_collectionId);
    final ok = await Get.find<LibraryPlaylistsController>().togglePin(content);
    showUndoSnackbar(
        target,
        !ok
            ? 'pinPlaylistLimit'.trParams({'count': '${LibraryPins.max}'})
            : pinning
                ? 'playlistPinned'.tr
                : 'playlistUnpinned'.tr);
  }

  void _showPlaySheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        // Sheet rows per RIFF_UI_RESTYLE.md §5.10.
        child: ListTileTheme.merge(
          titleTextStyle: Theme.of(ctx).textTheme.bodyLarge,
          iconColor: Theme.of(ctx).colorScheme.onSurface,
          child: IconTheme.merge(
            data: const IconThemeData(size: RiffComponentSizes.headerIcon),
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: Text('play'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _playFromOverlay();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shuffle),
                  title: Text('shuffle'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _playFromOverlay(shuffle: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: Text('playNext'.tr),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(ctx).pop();
                    _queueFromSheet(radio: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sensors),
                  title: Text('startRadio'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _queueFromSheet(radio: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: Text('viewAll'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openContent();
                  },
                ),
                if (_canPin) _pinTile(ctx, undoSnackbarTarget(context)),
                // Spotify's folders for Your Library.
                if (_canPin)
                  ListTile(
                    leading: const Icon(Icons.drive_file_move_outlined),
                    title: Text('moveToFolder'.tr),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showMoveToFolderSheet(context, content);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinTile(BuildContext sheet, UndoSnackbarTarget? target) {
    final pinned = LibraryPins.isPinned(_collectionId);
    return ListTile(
      leading: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
      title: Text(pinned ? 'unpinPlaylist'.tr : 'pinPlaylist'.tr),
      onTap: () {
        Navigator.of(sheet).pop();
        _togglePin(target);
      },
    );
  }

  /// The subtitle, after a pin in the accent when the playlist is pinned.
  Widget _subtitleLine(BuildContext context, Color? muted) {
    final line = Text(
      _subtitle(_isAlbum),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: muted,
          ),
    );
    if (!_canPin) return line;
    return Obx(() {
      LibraryPins.rev.value;
      if (!LibraryPins.isPinned(_collectionId)) return line;
      return Row(
        children: [
          Icon(
            Icons.push_pin_rounded,
            size: RiffComponentSizes.pinMark,
            color: Theme.of(context).colorScheme.secondary,
            semanticLabel: 'pinned'.tr,
          ),
          const SizedBox(width: RiffSpacing.xxs),
          Flexible(child: line),
        ],
      );
    });
  }

  Widget _cover(BuildContext context) {
    final Widget child;
    if (_isAlbum) {
      child = ImageWidget(
        size: size,
        album: content,
        borderRadius: RiffTokens.radiusSm,
      );
    } else if (content.isCloudPlaylist ||
        !(content.playlistId == 'LIBRP' ||
            content.playlistId == 'LIBFAV' ||
            content.playlistId == 'SongsCache' ||
            content.playlistId == 'SongDownloads')) {
      child = ImageWidget(
        size: size,
        playlist: content,
        borderRadius: RiffTokens.radiusSm,
        // A generated cover's title wraps before the play button.
        coverTitleRightInset: _playReach,
      );
    } else {
      // Riff's own lists (Favorites, Recently played, Cached, Downloads):
      // a generated colour cover with their glyph in white, as Spotify
      // gives Liked Songs its own art, instead of a grey square.
      child = ClipRRect(
        borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GeneratedCover(
                  seed: content.playlistId,
                  title: '',
                  size: size,
                  showTitle: false),
              Center(
                child: Icon(
                  content.playlistId == 'LIBRP'
                      ? Icons.history
                      : content.playlistId == 'LIBFAV'
                          ? Icons.favorite
                          : content.playlistId == 'SongsCache'
                              ? Icons.flight
                              : Icons.download,
                  color: RiffColors.of(context).onImage,
                  size: size * RiffCoverArt.glyphShare,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return child;
  }

  Widget _art(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          _cover(context),
          Positioned(
            right: _playInset,
            bottom: _playInset,
            child: Tooltip(
              message: "play".tr,
              child: Material(
                color: RiffColors.of(context).scrim.withOpacity(0.5),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    noteSearchOpen(context, content);
                    _playFromOverlay();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(_playPadding),
                    child: Icon(
                      Icons.play_circle_fill,
                      size: _playGlyph,
                      color: RiffColors.of(context).onImage,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A tap: [_onTap], kept among recent searches when it's a search
  /// result.
  void _open(BuildContext context) {
    noteSearchOpen(context, content);
    _onTap();
  }

  /// What a tap does: open the album / playlist / show page (the play
  /// button on a card's cover still plays).
  VoidCallback get _onTap => shouldPlayCollectionOnTap() &&
          (_isAlbum ||
              !isPodcastCollection(kind: _collectionKind, id: _collectionId))
      ? _playFromOverlay
      : _openContent;

  /// [asRow]: the cover, then the title and subtitle, with the hairline
  /// list rows have (§5.2).
  Widget _row(BuildContext context, Color? muted) {
    return Stack(
      children: [
        InkWell(
          onTap: () => _open(context),
          onLongPress: () => _showPlaySheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: HomeLayout.gutter, vertical: RiffSpacing.sm),
            child: Row(
              children: [
                SizedBox.square(dimension: size, child: _cover(context)),
                const SizedBox(width: RiffSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: RiffSpacing.xxs),
                      _subtitleLine(context, muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const RiffRowHairline(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.6);
    if (asRow) return _row(context, muted);
    return RiffPressScale(
        child: InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      // Open the album / playlist / show page; the play button on the
      // cover still plays.
      onTap: () => _open(context),
      onLongPress: () => _showPlaySheet(context),
      child: SizedBox(
        width: size,
        height: heightFor(context, size),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _art(context),
            const SizedBox(height: 8),
            Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 2),
            _subtitleLine(context, muted),
          ],
        ),
      ),
    ));
  }
}
