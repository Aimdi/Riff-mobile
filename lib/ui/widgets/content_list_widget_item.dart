import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../navigator.dart';
import '../player/player_controller.dart';
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';
import 'collection_play.dart';
import 'image_widget.dart';
import 'podcast_play.dart';
import 'snackbar.dart';

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

  bool get _isAlbum => content.runtimeType.toString() == "Album";

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

  void _openContent() {
    if (_isAlbum) {
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id,
          arguments: (content, content.browseId));
      return;
    }
    Get.toNamed(ScreenNavigationSetup.playlistScreen,
        id: ScreenNavigationSetup.id,
        arguments: [content, content.playlistId, showSimilarOnOpen]);
  }

  String get _collectionId => _isAlbum
      ? (content.browseId?.toString() ?? '')
      : (content.playlistId?.toString() ?? '');

  String? get _collectionKind =>
      _isAlbum ? null : content.kind?.toString();

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
            title: content.title?.toString() ?? '',
            shuffle: shuffle,
          );
          if (ok) return;
        }
      }
      final ok = await playCollection(
        isAlbum: _isAlbum,
        id: _collectionId,
        title: content.title?.toString() ?? '',
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

  void _snackOperationFailed() {
    final ctx = Get.context;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
      ctx,
      'operationFailed'.tr,
      size: SanckBarSize.MEDIUM,
    ));
  }

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

  void _showPlaySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      builder: (ctx) => SafeArea(
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
          ],
        ),
      ),
    );
  }

  Widget _art(BuildContext context) {
    final Widget child;
    if (_isAlbum) {
      child = ImageWidget(
        size: 112,
        album: content,
        borderRadius: RiffTokens.radiusSm,
      );
    } else if (content.isCloudPlaylist ||
        !(content.playlistId == 'LIBRP' ||
            content.playlistId == 'LIBFAV' ||
            content.playlistId == 'SongsCache' ||
            content.playlistId == 'SongDownloads')) {
      child = ImageWidget(
        size: 112,
        playlist: content,
        borderRadius: RiffTokens.radiusSm,
      );
    } else {
      child = Container(
          height: 112,
          width: 112,
          decoration: BoxDecoration(
              color: Theme.of(context).primaryColorLight,
              borderRadius: BorderRadius.circular(RiffTokens.radiusSm)),
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
          )));
    }
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        children: [
          child,
          Positioned(
            right: 4,
            bottom: 4,
            child: Tooltip(
              message: "play".tr,
              child: Material(
                color: Colors.black.withOpacity(0.5),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    _playFromOverlay();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 26,
                      color: Colors.white,
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

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.6);
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: shouldPlayCollectionOnTap() ? _playFromOverlay : _openContent,
      onLongPress: () => _showPlaySheet(context),
      child: SizedBox(
        width: 112,
        height: 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _art(context),
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
              _subtitle(_isAlbum),
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
