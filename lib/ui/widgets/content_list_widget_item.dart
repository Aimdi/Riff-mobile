import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/media_Item_builder.dart';
import '../../models/playling_from.dart';
import '../../services/music_service.dart';
import '../../services/piped_service.dart';
import '../../services/playlist_mix_service.dart';
import '../navigator.dart';
import '../player/player_controller.dart';
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';
import 'image_widget.dart';

bool _isSystemLibraryPlaylistId(String id) =>
    id == 'LIBRP' ||
    id == 'LIBFAV' ||
    id == 'SongsCache' ||
    id == 'SongDownloads';

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

  /// Play without opening the screen when tracks are a one-liner fetch
  /// ([MusicServices.getPlaylistOrAlbumSongs] / Hive / Piped). Falls back to
  /// opening the album/playlist if that path is empty or throws.
  Future<void> _playFromOverlay() async {
    try {
      final tracks = await _loadPlayTracks();
      if (tracks.isEmpty || !Get.isRegistered<PlayerController>()) {
        _openContent();
        return;
      }
      if (Get.isRegistered<PlaylistMixService>()) {
        Get.find<PlaylistMixService>().deactivatePlayback();
      }
      await Get.find<PlayerController>().playPlayListSong(
        tracks,
        0,
        playfrom: PlaylingFrom(
          name: content.title?.toString() ?? '',
          type: _isAlbum ? PlaylingFromType.ALBUM : PlaylingFromType.PLAYLIST,
        ),
      );
    } catch (_) {
      _openContent();
    }
  }

  Future<List<MediaItem>> _loadPlayTracks() async {
    if (_isAlbum) {
      final id = content.browseId?.toString() ?? '';
      if (isLibraryItem && id.isNotEmpty) {
        final local = await _tracksFromOpenBox(id);
        if (local.isNotEmpty) return local;
      }
      if (id.isEmpty || !Get.isRegistered<MusicServices>()) return const [];
      final result =
          await Get.find<MusicServices>().getPlaylistOrAlbumSongs(albumId: id);
      return List<MediaItem>.from(result['tracks'] ?? const []);
    }

    final id = content.playlistId?.toString() ?? '';
    if (id.isEmpty) return const [];

    if (content.isPipedPlaylist == true && Get.isRegistered<PipedServices>()) {
      return Get.find<PipedServices>().getPlaylistSongs(id);
    }

    final tryLocal = isLibraryItem ||
        content.isCloudPlaylist == false ||
        _isSystemLibraryPlaylistId(id);
    if (tryLocal) {
      final local = await _tracksFromOpenBox(id);
      if (local.isNotEmpty) {
        return id == 'LIBRP' ? local.reversed.toList() : local;
      }
      if (_isSystemLibraryPlaylistId(id) || content.isCloudPlaylist == false) {
        return const [];
      }
    }

    if (!Get.isRegistered<MusicServices>()) return const [];
    final result =
        await Get.find<MusicServices>().getPlaylistOrAlbumSongs(playlistId: id);
    return List<MediaItem>.from(result['tracks'] ?? const []);
  }

  /// Reads a local Hive song box. Callers only pass library / system ids.
  Future<List<MediaItem>> _tracksFromOpenBox(String id) async {
    try {
      if (!Hive.isBoxOpen(id)) {
        await Hive.openBox(id);
      }
      final tracks = <MediaItem>[];
      for (final raw in Hive.box(id).values) {
        try {
          final item = MediaItemBuilder.fromJson(raw);
          if (item.id.isNotEmpty) tracks.add(item);
        } catch (_) {}
      }
      return tracks;
    } catch (_) {
      return const [];
    }
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
      onTap: _openContent,
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
