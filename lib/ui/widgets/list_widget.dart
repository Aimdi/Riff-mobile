import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '../../models/artist.dart';
import '../../models/playling_from.dart';
import '../../models/playlist.dart';
import '/services/ban_service.dart';
import '../navigator.dart';
import '../player/player_controller.dart';
import 'image_widget.dart';
import 'snackbar.dart';
import 'song_list_tile.dart';
import 'songinfo_bottom_sheet.dart';

class ListWidget extends StatelessWidget with RemoveSongFromPlaylistMixin {
  const ListWidget(this.items, this.title, this.isCompleteList,
      {super.key,
      this.isPlaylistOrAlbum = false,
      this.isArtistSongs = false,
      this.playlist,
      this.album,
      this.artist,
      this.scrollController});
  final List<dynamic> items;
  final String title;
  final bool isCompleteList;
  final ScrollController? scrollController;

  /// Valid for songlist
  final bool isArtistSongs;
  final bool isPlaylistOrAlbum;
  final Playlist? playlist;
  final Album? album;
  final Artist? artist;

  /// Search / overview sections only show a short preview (View All opens
  /// the complete list). Capping avoids NestedScrollView height = N*extent
  /// which forced every child to build.
  static const int _overviewPreviewCount = 5;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            "No ${title.toLowerCase().tr}!",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
    } else if (title == "Videos" ||
        title.contains("Songs") ||
        title == "Episodes") {
      return isCompleteList
          ? Expanded(
              child: listViewSongVid(items,
                  isPlaylistOrAlbum: isPlaylistOrAlbum,
                  playlist: playlist,
                  album: album,
                  artist: artist,
                  sc: scrollController,
                  isArtistSongs: isArtistSongs))
          // Search overview: cap preview rows so NestedScrollView doesn't
          // force-build every song tile via items.length * extent height.
          : SizedBox(
              height: (items.length < _overviewPreviewCount
                      ? items.length
                      : _overviewPreviewCount) *
                  75.0,
              child: listViewSongVid(items,
                  maxItems: _overviewPreviewCount),
            );
    } else if (title.contains("playlists") || title == "Podcasts") {
      return listViewPlaylists(items, sc: scrollController);
    } else if (title == "Albums" || title == "Singles") {
      return listViewAlbums(items, sc: scrollController);
    } else if (title.contains('Artists')) {
      return isCompleteList
          ? Expanded(child: listViewArtists(items, sc: scrollController))
          : SizedBox(
              height: (items.length < _overviewPreviewCount
                      ? items.length
                      : _overviewPreviewCount) *
                  72.0,
              child: listViewArtists(items,
                  maxItems: _overviewPreviewCount),
            );
    }
    return const SizedBox.shrink();
  }

  Widget listViewSongVid(List<dynamic> items,
      {bool isPlaylistOrAlbum = false,
      Playlist? playlist,
      Album? album,
      Artist? artist,
      bool isArtistSongs = false,
      ScrollController? sc,
      int? maxItems}) {
    final playerController = Get.find<PlayerController>();
    final count = maxItems == null
        ? items.length
        : (items.length < maxItems ? items.length : maxItems);
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: isCompleteList ? 200 : 0,
        top: 0,
      ),
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      controller: sc,
      itemCount: count,
      // SongListTile rows are a fixed ~75px — enables cheaper scroll layout.
      itemExtent: 75,
      physics: isCompleteList
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final song = items[index] as MediaItem;
        return SongListTile(
          key: ValueKey(song.id),
          song: song,
          playlist: playlist,
          isPlaylistOrAlbum: isPlaylistOrAlbum,
          onTap: () {
            isArtistSongs
                // if song is from artist then play from artist
                ? playerController.playPlayListSong(
                    List<MediaItem>.from(items), index,
                    playfrom: PlaylingFrom(
                        type: PlaylingFromType.ARTIST,
                        name: artist?.name ?? "........."))
                :
                // if playlist is not null then play from playlist else play from album
                playlist != null && album == null
                    ? playerController.playPlayListSong(
                        List<MediaItem>.from(items), index,
                        playfrom: PlaylingFrom(
                          type: PlaylingFromType.PLAYLIST,
                          name: playlist.title,
                        ))
                    : playerController.pushSongToQueue(song);
          },
        );
      },
    );
  }

  Widget listViewPlaylists(List<dynamic> playlists, {ScrollController? sc}) {
    return Expanded(
      child: ListView.builder(
          padding: const EdgeInsets.only(
            bottom: 210,
            top: 0,
          ),
          controller: sc,
          itemCount: playlists.length,
          itemExtent: 120,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) => wideListTile(context,
              playlist: playlists[index],
              title: playlists[index].title,
              subtitle: playlists[index]?.description ?? "NA",
              subtitle2: "")),
    );
  }

  Widget listViewAlbums(List<dynamic> albums, {ScrollController? sc}) {
    return Expanded(
      child: ListView.builder(
          padding: const EdgeInsets.only(
            bottom: 210,
            top: 0,
          ),
          controller: sc,
          itemCount: albums.length,
          itemExtent: 120,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            String artistName = "";
            try {
              for (dynamic items in (albums[index].artists).sublist(1)) {
                artistName = "${artistName + items['name']},";
              }
              // ignore: empty_catches
            } catch (e) {}
            artistName = artistName.length > 16
                ? artistName.substring(0, 16)
                : artistName;
            return wideListTile(context,
                album: albums[index],
                title: albums[index].title,
                subtitle: artistName,
                subtitle2: albums[index].artists.isEmpty
                    ? "${albums[index].year}"
                    : "${(albums[index].artists[0]['name'])} • ${albums[index].year}");
          }),
    );
  }

  Widget listViewArtists(List<dynamic> artists,
      {ScrollController? sc, int? maxItems}) {
    final count = maxItems == null
        ? artists.length
        : (artists.length < maxItems ? artists.length : maxItems);
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: isCompleteList ? 200 : 0,
        top: 5,
      ),
      controller: sc,
      itemCount: count,
      itemExtent: 72,
      physics: isCompleteList
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) => ListTile(
        visualDensity: const VisualDensity(horizontal: -2, vertical: 0),
        onTap: () {
          Get.toNamed(ScreenNavigationSetup.artistScreen,
              id: ScreenNavigationSetup.id, arguments: [false, artists[index]]);
        },
        contentPadding: const EdgeInsets.only(top: 0, bottom: 0, left: 5),
        leading: ImageWidget(
          size: 56,
          artist: artists[index],
        ),
        title: Text(
          artists[index].name,
          maxLines: 1,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          artists[index].subscribers,
          maxLines: 1,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }

  Widget wideListTile(BuildContext context,
      {dynamic album,
      dynamic playlist,
      required String title,
      required String subtitle,
      required String subtitle2}) {
    return InkWell(
      onTap: () {
        if (album != null) {
          Get.toNamed(ScreenNavigationSetup.albumScreen,
              id: ScreenNavigationSetup.id, arguments: (album, album.browseId));
        } else {
          Get.toNamed(ScreenNavigationSetup.playlistScreen,
              id: ScreenNavigationSetup.id,
              arguments: [playlist, playlist.playlistId]);
        }
      },
      onLongPress: () {
        final isAlbum = album != null;
        final id = isAlbum ? album.browseId : playlist.playlistId;
        final name = isAlbum ? album.title : playlist.title;
        if (id == null) return;
        showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
          ),
          builder: (ctx) => Wrap(children: [
            ListTile(
              leading: const Icon(Icons.block),
              title:
                  Text(isAlbum ? "neverPlayAlbum".tr : "neverPlayPlaylist".tr),
              onTap: () {
                BanService.banCollection(
                    id, name, isAlbum ? "album" : "playlist");
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(snackbar(
                    context, "${"collectionBannedMsg".tr} $name",
                    size: SanckBarSize.BIG));
              },
            ),
          ]),
        );
      },
      child: SizedBox(
        height: 120,
        child: Padding(
          padding: const EdgeInsets.only(top: 10.0, bottom: 10),
          child: Row(
            children: [
              ImageWidget(
                size: 100,
                album: album,
                playlist: playlist,
              ),
              const SizedBox(
                width: 20,
              ),
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.only(right: 10.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      subtitle2,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ))
            ],
          ),
        ),
      ),
    );
  }
}
