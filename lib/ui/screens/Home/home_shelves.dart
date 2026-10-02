import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/home_shelf_content.dart';
import '/models/playlist.dart';
import '/services/discovery/discovery_types.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import 'home_layout.dart';
import 'home_screen_controller.dart';

/// Every YouTube Music home shelf, in full, in the order the feed sent
/// them: songs as a two-row grid, albums and playlists as cover shelves,
/// artists as round covers.
class HomeShelves extends StatelessWidget {
  const HomeShelves({super.key, this.chipFeed = false});

  /// Show the shelves of the selected chip instead of the plain feed.
  final bool chipFeed;

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    return Obx(() {
      final shelves = chipFeed
          ? home.chipContent.toList()
          : [...home.middleContent, ...home.fixedContent];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final shelf in shelves) _shelf(home, shelf),
        ],
      );
    });
  }

  Widget _shelf(HomeScreenController home, dynamic shelf) {
    if (shelf is SongContent) {
      return HomeSongShelf(
        title: shelf.title,
        songs: shelf.songs,
        scrollController: home.scrollControllerFor(
            '${chipFeed ? 'chip_' : ''}shelf_${shelf.title}'),
      );
    }
    if (shelf is ArtistShelf) {
      return HomeArtistShelf(title: shelf.title, artists: shelf.artists);
    }
    if (shelf is AlbumContent || shelf is PlaylistContent) {
      return ContentListWidget(
        content: shelf,
        scrollController: home.scrollControllerFor(
            '${chipFeed ? 'chip_' : ''}shelf_${shelf.title}'),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Two rows of song tiles that page sideways, a column at a time.
class HomeSongShelf extends StatelessWidget {
  const HomeSongShelf({
    super.key,
    required this.title,
    required this.songs,
    this.scrollController,
    this.source = DiscoverySource.home,
  });

  final String title;
  final List<MediaItem> songs;
  final ScrollController? scrollController;
  final DiscoverySource source;

  static const rowHeight = 60.0;
  static const rowGap = 4.0;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    final player = Get.find<PlayerController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title),
        SizedBox(
          height: rowHeight * 2 + rowGap,
          child: LayoutBuilder(builder: (context, constraints) {
            // Leave a peek of the next column so the grid reads as scrollable.
            final rowWidth = (constraints.maxWidth - HomeLayout.gutter - 40)
                .clamp(220.0, 340.0);
            return GridView.builder(
              controller: scrollController,
              physics: const BouncingScrollPhysics(),
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
              itemCount: songs.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: rowWidth,
                crossAxisSpacing: rowGap,
                mainAxisSpacing: HomeLayout.cardGap,
              ),
              itemBuilder: (context, i) => _SongTile(
                song: songs[i],
                onTap: () async {
                  final ok =
                      await player.playPlayListSong(songs, i, source: source);
                  if (!ok) snackOperationFailed();
                },
                onLongPress: () => showCurrentSongSheet(
                    song: songs[i],
                    context: player.homeScaffoldkey.currentContext),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile(
      {required this.song, required this.onTap, required this.onLongPress});
  final MediaItem song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
              child: ImageWidget(song: song, size: 52, borderRadius: 0),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardTitleStyle(context)
                          .copyWith(fontSize: 14.5)),
                  const SizedBox(height: 3),
                  Text(song.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardSubtitleStyle(context)
                          .copyWith(fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.play_arrow_rounded,
                size: 22, color: homeMutedColor(context)),
          ],
        ),
      ),
    );
  }
}

/// Round artist covers with the name underneath; tap opens the artist.
class HomeArtistShelf extends StatelessWidget {
  const HomeArtistShelf({super.key, required this.title, required this.artists});
  final String title;
  final List<Artist> artists;

  static const size = 104.0;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title),
        SizedBox(
          height: size + 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            itemCount: artists.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: HomeLayout.cardGap),
            itemBuilder: (context, i) {
              final artist = artists[i];
              return SizedBox(
                width: size,
                child: InkWell(
                  borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
                  onTap: () => Get.toNamed(ScreenNavigationSetup.artistScreen,
                      id: ScreenNavigationSetup.id,
                      arguments: [true, artist.browseId]),
                  child: Column(
                    children: [
                      ClipOval(
                        child: ImageWidget(
                            artist: artist, size: size, borderRadius: 0),
                      ),
                      const SizedBox(height: 8),
                      Text(artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: homeCardTitleStyle(context)),
                      if ((artist.subscribers ?? '').isNotEmpty)
                        Text(artist.subscribers!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: homeCardSubtitleStyle(context)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
