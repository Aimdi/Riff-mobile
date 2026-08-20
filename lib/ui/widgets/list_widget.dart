import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '../../models/artist.dart';
import '../../models/playling_from.dart';
import '../../models/playlist.dart';
import '/services/ban_service.dart';
import '/services/discovery/discovery_types.dart';
import '../navigator.dart';
import '../player/player_controller.dart';
import 'collection_play.dart';
import 'empty_play_hint.dart';
import 'image_widget.dart';
import 'snackbar.dart';
import 'song_list_tile.dart';
import 'songinfo_bottom_sheet.dart';

/// Search overview rows and Songs/Videos/Episodes lists play as a queue.
/// Playlist/album/artist complete lists keep their own play-from path.
bool shouldPlaySearchRowsAsQueue({
  required bool isCompleteList,
  required String title,
}) =>
    !isCompleteList ||
    title.contains('Songs') ||
    title == 'Videos' ||
    title == 'Episodes';

/// Empty list copy — never the raw "No ${title}!" template.
String emptyListLabelKey(String title, {bool searchContext = false}) {
  if (title == 'Videos' ||
      title.contains('Songs') ||
      title == 'Episodes') {
    return 'emptyPlaylist';
  }
  if (searchContext) return 'noResults';
  return 'noBookmarks';
}

/// Search album/playlist long-press play actions (plus Ban).
List<String> wideCollectionLongPressPlayKeys() =>
    const ['play', 'shuffle', 'playNext', 'startRadio'];

void _snackPlayFailed() => snackOperationFailed();

class ListWidget extends StatelessWidget with RemoveSongFromPlaylistMixin {
  const ListWidget(this.items, this.title, this.isCompleteList,
      {super.key,
      this.isPlaylistOrAlbum = false,
      this.isArtistSongs = false,
      this.playlist,
      this.album,
      this.artist,
      this.searchContext = false,
      this.scrollController});
  final List<dynamic> items;
  final String title;
  final bool isCompleteList;
  final ScrollController? scrollController;
  final bool searchContext;

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
        child: EmptyPlayHint(
            message: emptyListLabelKey(title, searchContext: searchContext).tr),
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
                  isPlaylistOrAlbum: isPlaylistOrAlbum,
                  playlist: playlist,
                  album: album,
                  artist: artist,
                  isArtistSongs: isArtistSongs,
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
          onTap: () async {
            final bool ok;
            if (isArtistSongs) {
              ok = await playerController.playPlayListSong(
                  List<MediaItem>.from(items), index,
                  playfrom: PlaylingFrom(
                      type: PlaylingFromType.ARTIST,
                      name: artist?.name ?? "........."));
            } else if (playlist != null && album == null) {
              ok = await playerController.playPlayListSong(
                  List<MediaItem>.from(items), index,
                  playfrom: PlaylingFrom(
                    type: PlaylingFromType.PLAYLIST,
                    name: playlist.title,
                  ));
            } else if (shouldPlaySearchRowsAsQueue(
                    isCompleteList: isCompleteList, title: title) &&
                items.isNotEmpty &&
                items.first is MediaItem) {
              ok = await playerController.playPlayListSong(
                  List<MediaItem>.from(items), index,
                  source: DiscoverySource.search);
            } else {
              ok = await playerController.pushSongToQueue(song);
            }
            if (!ok) _snackPlayFailed();
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
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          visualDensity: const VisualDensity(horizontal: -2, vertical: 0),
          onTap: () => shouldPlayCollectionOnTap()
              ? _playArtistRow(artist)
              : _openArtist(artist),
          onLongPress: () => _showArtistActions(context, artist),
          contentPadding: const EdgeInsets.only(top: 0, bottom: 0, left: 5),
          leading: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              children: [
                ImageWidget(
                  size: 56,
                  artist: artist,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: 'play'.tr,
                    child: Material(
                      color: Colors.black.withOpacity(0.5),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _playArtistRow(artist),
                        child: const Padding(
                          padding: EdgeInsets.all(1),
                          child: Icon(
                            Icons.play_circle_fill,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            artist.name,
            maxLines: 1,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            artist.subscribers ?? '',
            maxLines: 1,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        );
      },
    );
  }

  void _openArtist(dynamic artist) {
    Get.toNamed(ScreenNavigationSetup.artistScreen,
        id: ScreenNavigationSetup.id, arguments: [false, artist]);
  }

  Future<void> _playArtistRow(
    dynamic artist, {
    bool shuffle = false,
    bool radio = false,
  }) async {
    if (artist is! Artist) {
      _openArtist(artist);
      return;
    }
    final ok =
        await playArtist(artist, shuffle: shuffle, radio: radio);
    if (!ok) {
      _snackPlayFailed();
      _openArtist(artist);
    }
  }

  void _showArtistActions(BuildContext context, dynamic artist) {
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
                _playArtistRow(artist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: Text('shuffle'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _playArtistRow(artist, shuffle: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sensors),
              title: Text('startRadio'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _playArtistRow(artist, radio: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text('viewAll'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _openArtist(artist);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openWideTile({dynamic album, dynamic playlist}) {
    if (album != null) {
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id, arguments: (album, album.browseId));
      return;
    }
    Get.toNamed(ScreenNavigationSetup.playlistScreen,
        id: ScreenNavigationSetup.id,
        arguments: [playlist, playlist.playlistId]);
  }

  Future<void> _playWideTile({
    dynamic album,
    dynamic playlist,
    required bool shuffle,
  }) async {
    final isAlbum = album != null;
    final id = isAlbum
        ? album.browseId?.toString() ?? ''
        : playlist.playlistId?.toString() ?? '';
    final name = isAlbum ? album.title : playlist.title;
    final ok = await playCollection(
      isAlbum: isAlbum,
      id: id,
      title: name?.toString() ?? '',
      shuffle: shuffle,
      isPipedPlaylist: !isAlbum && playlist.isPipedPlaylist == true,
      isCloudPlaylist: isAlbum || playlist.isCloudPlaylist != false,
    );
    if (!ok) {
      _snackPlayFailed();
      _openWideTile(album: album, playlist: playlist);
    }
  }

  Future<void> _queueWideTile({
    dynamic album,
    dynamic playlist,
    required bool radio,
  }) async {
    final isAlbum = album != null;
    final id = isAlbum
        ? album.browseId?.toString() ?? ''
        : playlist.playlistId?.toString() ?? '';
    final tracks = await loadCollectionPlayTracks(
      isAlbum: isAlbum,
      id: id,
      isPipedPlaylist: !isAlbum && playlist.isPipedPlaylist == true,
      isCloudPlaylist: isAlbum || playlist.isCloudPlaylist != false,
    );
    if (tracks.isEmpty || !Get.isRegistered<PlayerController>()) {
      final ctx = Get.context;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
          ctx,
          'operationFailed'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
      return;
    }
    final player = Get.find<PlayerController>();
    if (radio) {
      final ok = await player.startRadio(tracks.first);
      if (!ok) {
        final ctx = Get.context;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
            ctx,
            'operationFailed'.tr,
            size: SanckBarSize.MEDIUM,
          ));
        }
      }
      return;
    }
    final queued = await player.playNextList(tracks);
    if (!queued) {
      final ctx = Get.context;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
          ctx,
          'operationFailed'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
    }
  }

  Widget wideListTile(BuildContext context,
      {dynamic album,
      dynamic playlist,
      required String title,
      required String subtitle,
      required String subtitle2}) {
    return InkWell(
      onTap: () => shouldPlayCollectionOnTap()
          ? _playWideTile(album: album, playlist: playlist, shuffle: false)
          : _openWideTile(album: album, playlist: playlist),
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
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text('play'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _playWideTile(
                    album: album, playlist: playlist, shuffle: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: Text('shuffle'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _playWideTile(
                    album: album, playlist: playlist, shuffle: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text('playNext'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _queueWideTile(
                    album: album, playlist: playlist, radio: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sensors),
              title: Text('startRadio'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _queueWideTile(
                    album: album, playlist: playlist, radio: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title:
                  Text(isAlbum ? "neverPlayAlbum".tr : "neverPlayPlaylist".tr),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ok = await BanService.banCollection(
                    id, name, isAlbum ? "album" : "playlist");
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(snackbar(
                    context,
                    ok
                        ? "${"collectionBannedMsg".tr} $name"
                        : "operationFailed".tr,
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
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  children: [
                    ImageWidget(
                      size: 100,
                      album: album,
                      playlist: playlist,
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Tooltip(
                        message: 'play'.tr,
                        child: Material(
                          color: Colors.black.withOpacity(0.5),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              _playWideTile(
                                  album: album,
                                  playlist: playlist,
                                  shuffle: false);
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
