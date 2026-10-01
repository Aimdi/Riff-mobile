import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/models/thumbnail.dart';
import 'package:harmonymusic/ui/widgets/playlist_album_scroll_behaviour.dart';
import 'package:share_plus/share_plus.dart';

import '../../player/player_controller.dart';
import '../../widgets/collection_header.dart';
import '../../widgets/header_hero_fade.dart';
import '../../navigator.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/shimmer_widgets/song_list_shimmer.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../../widgets/sort_widget.dart';
import 'album_screen_controller.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tag = key.hashCode.toString();
    final albumController = (Get.isRegistered<AlbumScreenController>(tag: tag))
        ? Get.find<AlbumScreenController>(tag: tag)
        : Get.put(AlbumScreenController(), tag: tag);
    final size = MediaQuery.of(context).size;
    final playerController = Get.find<PlayerController>();
    final landscape = size.width > size.height;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          final scrollOffset = scrollInfo.metrics.pixels;

          if (landscape) {
            if (albumController.scrollOffset.value != 0) {
              albumController.scrollOffset.value = 0;
            }
          } else if ((albumController.scrollOffset.value - scrollOffset).abs() >
              2) {
            // Throttle Opacity rebuilds while the hero parallax scrolls.
            albumController.scrollOffset.value = scrollOffset;
          }
          if (scrollOffset > 270 || (landscape && scrollOffset > 225)) {
            albumController.appBarTitleVisible.value = true;
          } else {
            albumController.appBarTitleVisible.value = false;
          }
          return true;
        },
        child: Stack(
          children: [
            Obx(
              () => albumController.isContentFetched.isTrue
                  ? Positioned(
                      top: landscape
                          ? 0
                          : -.25 * albumController.scrollOffset.value,
                      right: landscape ? 0 : null,
                      child: Obx(() {
                        final opacityValue = 1 -
                            albumController.scrollOffset.value /
                                (size.width - 100);
                        return HeaderHeroFade(
                            opacity: opacityValue < 0 ||
                                    albumController.isSearchingOn.isTrue
                                ? 0
                                : opacityValue,
                            color: Theme.of(context).canvasColor,
                            leftShadowOffset: -size.height,
                            bottomShadowOffset:
                                landscape ? size.height : size.width + 80,
                            child: CachedNetworkImage(
                              imageUrl: Thumbnail(
                                      albumController.album.value.thumbnailUrl)
                                  .extraHigh,
                              fit: landscape
                                  ? BoxFit.fitHeight
                                  : BoxFit.fitWidth,
                              width: landscape ? null : size.width,
                              height: landscape ? size.height : null,
                              memCacheWidth: landscape
                                  ? null
                                  : (size.width *
                                          MediaQuery.devicePixelRatioOf(
                                              context))
                                      .round(),
                              memCacheHeight: landscape
                                  ? (size.height *
                                          MediaQuery.devicePixelRatioOf(
                                              context))
                                      .round()
                                  : null,
                              errorWidget: (_, __, ___) => CachedNetworkImage(
                                imageUrl:
                                    albumController.album.value.thumbnailUrl,
                                fit: landscape
                                    ? BoxFit.fitHeight
                                    : BoxFit.fitWidth,
                                width: landscape ? null : size.width,
                                height: landscape ? size.height : null,
                                memCacheWidth: landscape
                                    ? null
                                    : (size.width *
                                            MediaQuery.devicePixelRatioOf(
                                                context))
                                        .round(),
                                memCacheHeight: landscape
                                    ? (size.height *
                                            MediaQuery.devicePixelRatioOf(
                                                context))
                                        .round()
                                    : null,
                                errorWidget: (_, __, ___) => Container(
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            ));
                      }))
                  : SizedBox(
                      height: size.width,
                      width: size.width,
                    ),
            ),
            Column(
              children: [
                Obx(() => CollectionTopBar(
                      title: albumController.album.value.title,
                      showTitle: albumController.appBarTitleVisible.isTrue,
                    )),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 800,
                      ),
                      child: Obx(
                        () => ScrollConfiguration(
                          behavior: PlaylistAlbumScrollBehaviour(),
                          child: ListView.builder(
                            padding: EdgeInsets.only(
                              top: albumController.isSearchingOn.isTrue
                                  ? 0
                                  : landscape
                                      ? 110
                                      : 160,
                              bottom: 200,
                            ),
                            itemCount: albumController.songList.isEmpty
                                ? 4
                                : albumController.songList.length + 3,
                            itemBuilder: (_, index) {
                              if (index == 0) {
                                return FadeTransition(
                                  opacity: albumController.scaleAnimation,
                                  child: _header(context, albumController),
                                );
                              } else if (index == 1) {
                                return _actions(context, albumController,
                                    playerController);
                              } else if (index == 2) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: SizedBox(
                                    height: albumController.isSearchingOn.isTrue
                                        ? 60
                                        : 44,
                                    child: Obx(
                                      () => SortWidget(
                                        tag: albumController
                                            .album.value.browseId,
                                        screenController: albumController,
                                        isSearchFeatureRequired: true,
                                        itemCountTitle:
                                            "${albumController.songList.length}",
                                        itemIcon: Icons.music_note,
                                        requiredSortTypes:
                                            buildSortTypeSet(false, true),
                                        onSort: albumController.onSort,
                                        onSearch: albumController.onSearch,
                                        onSearchClose:
                                            albumController.onSearchClose,
                                        onSearchStart:
                                            albumController.onSearchStart,
                                        startAdditionalOperation:
                                            albumController
                                                .startAdditionalOperation,
                                        selectAll: albumController.selectAll,
                                        performAdditionalOperation:
                                            albumController
                                                .performAdditionalOperation,
                                        cancelAdditionalOperation:
                                            albumController
                                                .cancelAdditionalOperation,
                                      ),
                                    ),
                                  ),
                                );
                              } else if (albumController
                                      .isContentFetched.isFalse ||
                                  albumController.songList.isEmpty) {
                                return SizedBox(
                                  height: 300,
                                  child:
                                      albumController.isContentFetched.isFalse
                                          ? const SongListShimmer(
                                              itemCount: 6, topPadding: 8)
                                          : Center(
                                              child: Text(
                                                "emptyPlaylist".tr,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                            ),
                                );
                              }

                              return Padding(
                                padding:
                                    const EdgeInsets.only(left: 4, right: 4),
                                child: SongListTile(
                                    onTap: () {
                                      _playAlbumFrom(
                                        playerController,
                                        albumController,
                                        index - 3,
                                      );
                                    },
                                    song: albumController.songList[index - 3],
                                    isPlaylistOrAlbum: true,
                                    thumbReplacementWithIndex: true,
                                    index: index - 2),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AlbumScreenController albumController) {
    final album = albumController.album.value;
    final artists = (album.artists ?? const [])
        .map((e) => '${e['name'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
    final firstArtistId = (album.artists?.isNotEmpty ?? false)
        ? album.artists!.first['id']?.toString()
        : null;
    return CollectionHeader(
      cover: ImageWidget(size: 96, album: album),
      title: album.title,
      subtitle: artists,
      onSubtitleTap: firstArtistId == null || firstArtistId.isEmpty
          ? null
          : () => Get.toNamed(ScreenNavigationSetup.artistScreen,
              id: ScreenNavigationSetup.id, arguments: [true, firstArtistId]),
      // `description` is the release type ("Album", "EP", "Single") unless
      // YouTube sent a real description — keep only the short type label.
      meta: collectionMetaLine(albumController.songList.toList(), lead: [
        (album.description ?? '').length <= 16 ? album.description : null,
        album.year,
      ]),
      onCoverTap: () {
        if (albumController.songList.isEmpty ||
            !Get.isRegistered<PlayerController>()) {
          return;
        }
        _playAlbumFrom(Get.find<PlayerController>(), albumController, 0);
      },
    );
  }

  Widget _actions(BuildContext context, AlbumScreenController albumController,
      PlayerController playerController) {
    void snack(String key) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(snackbar(context, key.tr, size: SanckBarSize.MEDIUM));
    }

    final songs = albumController.songList.toList();
    return CollectionActionRow(
      onPlay: songs.isEmpty
          ? null
          : () => _playAlbumFrom(playerController, albumController, 0),
      onShuffle: songs.isEmpty
          ? null
          : () => _playAlbumFrom(playerController, albumController, 0,
              shuffle: true),
      leading: [
        Obx(() => CollectionSaveButton(
              saved: albumController.isAddedToLibrary.isTrue,
              onPressed: () {
                final add = albumController.isAddedToLibrary.isFalse;
                albumController
                    .addNremoveFromLibrary(albumController.album.value,
                        add: add)
                    .then((ok) => snack(ok
                        ? add
                            ? "albumBookmarkAddAlert"
                            : "albumBookmarkRemoveAlert"
                        : "operationFailed"));
              },
            )),
        Obx(() => CollectionDownloadButton(
              id: albumController.album.value.browseId,
              songs: () => albumController.songList.toList(),
              isDownloaded: albumController.isDownloaded.isTrue,
              tooltip: "downloadAlbumSongs".tr,
            )),
      ],
      menu: [
        CollectionMenuItem(Icons.playlist_play_rounded, "playNext".tr,
            () async {
          final ok = await playerController
              .playNextList(albumController.songList.toList());
          snack(ok ? "playnextMsg" : "operationFailed");
        }),
        CollectionMenuItem(Icons.queue_music_rounded, "enqueueAlbumSongs".tr,
            () async {
          final ok = await playerController
              .enqueueSongList(albumController.songList.toList());
          snack(ok ? "songEnqueueAlert" : "operationFailed");
        }),
        CollectionMenuItem(Icons.sensors, "startRadio".tr, () async {
          final list = albumController.songList.toList();
          if (list.isEmpty) return snack("radioNotAvailable");
          final ok = await playerController.startRadio(list.first);
          if (!ok) snack("radioNotAvailable");
        }),
        CollectionMenuItem(
            Icons.share_outlined,
            "shareAlbum".tr,
            () => Share.share(
                "https://youtube.com/playlist?list=${albumController.album.value.audioPlaylistId}")),
      ],
    );
  }

  Future openBottomSheet(BuildContext context, MediaItem song) {
    return showModalBottomSheet(
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      isScrollControlled: true,
      context: context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (context) => SongInfoBottomSheet(song),
    ).whenComplete(() => Get.delete<SongInfoController>());
  }
}

Future<void> _playAlbumFrom(
  PlayerController playerController,
  AlbumScreenController albumController,
  int index, {
  bool shuffle = false,
}) async {
  final songs = List<MediaItem>.from(albumController.songList);
  if (shuffle) songs.shuffle();
  final ok = await playerController.playPlayListSong(
    songs,
    index,
    playfrom: PlaylingFrom(
      name: albumController.album.value.title,
      type: PlaylingFromType.ALBUM,
    ),
  );
  if (!ok) snackOperationFailed();
}
