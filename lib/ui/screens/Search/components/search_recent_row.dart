import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_item_extras.dart';
import '/models/playlist.dart';
import '/services/discovery/discovery_types.dart';
import '/services/search_recents.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/podcast_play.dart' show isPodcastCollection;
import '../../../navigator.dart';
import '../../Home/home_layout.dart';
import '../search_play_top.dart' show showSearchPlayFailed;

/// What a recent search is, then who it's by: "Song · Artist",
/// "Album · Artist", "Artist", "Playlist", "Podcast".
String searchRecentSubtitle(SearchRecent recent) {
  final (kind, by) = switch (recent.item) {
    final MediaItem song => (
        song.isPodcastEpisode ? 'episodeKind'.tr : 'songKind'.tr,
        song.artist
      ),
    Artist() => ('artist'.tr, null),
    final Album album => (
        'album'.tr,
        (album.artists ?? const []).isEmpty
            ? null
            : '${album.artists!.first['name'] ?? ''}'
      ),
    final Playlist playlist =>
      isPodcastCollection(kind: playlist.kind, id: playlist.playlistId)
          ? ('podcastKind'.tr, null)
          : ('playlist'.tr, null),
    _ => ('', null),
  };
  return [kind, if (by != null && by.trim().isNotEmpty) by.trim()].join(' · ');
}

/// One recent search (Spotify's and Apple Music's recent searches): its
/// cover, its name and what it is; a tap plays the song or opens the
/// artist, album, playlist or podcast again, the trailing ✕ forgets it.
/// Laid out as the recent search rows of text ([SearchRow]). Also what
/// YouTube Music suggests as you type, kept as a recent search once opened
/// ([removable] false: nothing to forget yet).
class SearchRecentRow extends StatelessWidget {
  const SearchRecentRow(
      {super.key, required this.recent, this.removable = true});

  final SearchRecent recent;
  final bool removable;

  String get _title => switch (recent.item) {
        final MediaItem song => song.title,
        final Artist artist => artist.name,
        final Album album => album.title,
        final Playlist playlist => playlist.title,
        _ => '',
      };

  Future<void> _open(BuildContext context) async {
    // Opened again: first in the list.
    await SearchRecents.note(recent.item);
    switch (recent.item) {
      case final MediaItem song:
        if (!Get.isRegistered<PlayerController>()) return;
        final ok = await Get.find<PlayerController>()
            .playPlayListSong([song], 0, source: DiscoverySource.search);
        if (!ok && context.mounted) showSearchPlayFailed(context);
      case final Artist artist:
        Get.toNamed(ScreenNavigationSetup.artistScreen,
            id: ScreenNavigationSetup.id, arguments: [false, artist]);
      case final Album album:
        Get.toNamed(ScreenNavigationSetup.albumScreen,
            id: ScreenNavigationSetup.id, arguments: (album, album.browseId));
      case final Playlist playlist:
        Get.toNamed(ScreenNavigationSetup.playlistScreen,
            id: ScreenNavigationSetup.id,
            arguments: [playlist, playlist.playlistId, false]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = recent.item;
    return InkWell(
      onTap: () => _open(context),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.dividerColor, width: 0),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
              left: HomeLayout.gutter,
              top: RiffSpacing.sm,
              right: removable
                  ? HomeLayout.gutter - RiffSpacing.sm
                  : HomeLayout.gutter,
              bottom: RiffSpacing.sm),
          child: Row(
            children: [
              ImageWidget(
                size: RiffComponentSizes.rowArt,
                song: item is MediaItem ? item : null,
                artist: item is Artist ? item : null,
                album: item is Album ? item : null,
                playlist: item is Playlist ? item : null,
              ),
              const SizedBox(width: RiffSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: scheme.onSurface)),
                    const SizedBox(height: RiffSpacing.xxs),
                    Text(searchRecentSubtitle(recent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (removable)
                IconButton(
                  tooltip: 'clear'.tr,
                  iconSize: RiffComponentSizes.trailingIcon,
                  color: scheme.onSurfaceVariant,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(RiffComponentSizes.iconHit),
                  ),
                  onPressed: () => SearchRecents.remove(recent),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
