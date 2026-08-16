import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/models/thumbnail.dart';
import 'package:harmonymusic/ui/widgets/playlist_album_scroll_behaviour.dart';
import 'package:share_plus/share_plus.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../../services/downloader.dart';
import '../../player/player_controller.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/loader.dart';
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
                        return Opacity(
                            opacity: opacityValue < 0 ||
                                    albumController.isSearchingOn.isTrue
                                ? 0
                                : opacityValue,
                            child: DecoratedBox(
                                position: DecorationPosition.foreground,
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).canvasColor,
                                      spreadRadius: 200,
                                      blurRadius: 100,
                                      offset: Offset(-size.height, 0),
                                    ),
                                    BoxShadow(
                                      color: Theme.of(context).canvasColor,
                                      spreadRadius: 200,
                                      blurRadius: 100,
                                      offset: Offset(
                                          0,
                                          landscape
                                              ? size.height
                                              : size.width + 80),
                                    )
                                  ],
                                ),
                                child: CachedNetworkImage(
                                  imageUrl: Thumbnail(albumController
                                          .album.value.thumbnailUrl)
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
                                  errorWidget: (_, __, ___) =>
                                      CachedNetworkImage(
                                    imageUrl: albumController
                                        .album.value.thumbnailUrl,
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                  ),
                                )));
                      }))
                  : SizedBox(
                      height: size.width,
                      width: size.width,
                    ),
            ),
            Column(
              children: [
                Container(
                  padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 10,
                      left: 10,
                      right: 10),
                  height: 80,
                  child: Center(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: IconButton(
                              tooltip: "back".tr,
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.arrow_back_ios)),
                        ),
                        Expanded(
                          child: Obx(
                            () => Marquee(
                              delay: const Duration(milliseconds: 300),
                              duration: const Duration(seconds: 5),
                              id: "${albumController.album.value.title.hashCode.toString()}_appbar",
                              child: Text(
                                albumController.appBarTitleVisible.isTrue
                                    ? albumController.album.value.title
                                    : "",
                                maxLines: 1,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                                      ? 150
                                      : 200,
                              bottom: 200,
                            ),
                            itemCount: albumController.songList.isEmpty
                                ? 4
                                : albumController.songList.length + 3,
                            itemBuilder: (_, index) {
                              if (index == 0) {
                                return Padding(
                                  padding: EdgeInsets.only(
                                      left:
                                          GetPlatform.isDesktop ? 15.0 : 10.0),
                                  child: SizedBox(
                                      height: 40,
                                      child: Row(
                                        children: [
                                          // Bookmark button
                                          Obx(() => IconButton(
                                              tooltip: albumController
                                                      .isAddedToLibrary.isFalse
                                                  ? "addToLibrary".tr
                                                  : "removeFromLibrary".tr,
                                              splashRadius: 10,
                                              onPressed: () {
                                                final add = albumController
                                                    .isAddedToLibrary.isFalse;
                                                albumController
                                                    .addNremoveFromLibrary(
                                                        albumController
                                                            .album.value,
                                                        add: add)
                                                    .then((value) {
                                                  if (!context.mounted) return;

                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(snackbar(
                                                          context,
                                                          value
                                                              ? add
                                                                  ? "albumBookmarkAddAlert"
                                                                      .tr
                                                                  : "albumBookmarkRemoveAlert"
                                                                      .tr
                                                              : "operationFailed"
                                                                  .tr,
                                                          size: SanckBarSize
                                                              .MEDIUM));
                                                });
                                              },
                                              icon: Icon(albumController
                                                      .isAddedToLibrary.isFalse
                                                  ? Icons.bookmark_add
                                                  : Icons.bookmark_added))),
                                          // Play button
                                          IconButton(
                                              tooltip: "play".tr,
                                              onPressed: () {
                                                playerController
                                                    .playPlayListSong(
                                                        List<MediaItem>.from(
                                                            albumController
                                                                .songList),
                                                        0,
                                                        playfrom: PlaylingFrom(
                                                            name:
                                                                albumController
                                                                    .album
                                                                    .value
                                                                    .title,
                                                            type:
                                                                PlaylingFromType
                                                                    .ALBUM));
                                              },
                                              icon: Icon(
                                                Icons.play_circle,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color,
                                              )),
                                          // Shuffle button
                                          IconButton(
                                              tooltip: "shuffle".tr,
                                              onPressed: () {
                                                final songsToplay =
                                                    List<MediaItem>.from(
                                                        albumController
                                                            .songList);
                                                songsToplay.shuffle();
                                                playerController
                                                    .playPlayListSong(
                                                        songsToplay,
                                                        0,
                                                        playfrom: PlaylingFrom(
                                                            name:
                                                                albumController
                                                                    .album
                                                                    .value
                                                                    .title,
                                                            type:
                                                                PlaylingFromType
                                                                    .ALBUM));
                                              },
                                              icon: Icon(
                                                Icons.shuffle,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color,
                                              )),
                                          // Enqueue button
                                          IconButton(
                                              tooltip: "enqueueAlbumSongs".tr,
                                              onPressed: () async {
                                                final ok =
                                                    await Get.find<
                                                            PlayerController>()
                                                        .enqueueSongList(
                                                            albumController
                                                                .songList
                                                                .toList());
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(snackbar(
                                                        context,
                                                        ok
                                                            ? "songEnqueueAlert"
                                                                .tr
                                                            : "operationFailed"
                                                                .tr,
                                                        size: SanckBarSize
                                                            .MEDIUM));
                                              },
                                              icon: Icon(
                                                Icons.merge,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color,
                                              )),
                                          // Play next
                                          IconButton(
                                              tooltip: "playNext".tr,
                                              onPressed: () async {
                                                final ok = await playerController
                                                    .playNextList(
                                                        albumController.songList
                                                            .toList());
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(snackbar(
                                                        context,
                                                        ok
                                                            ? "playnextMsg".tr
                                                            : "operationFailed"
                                                                .tr,
                                                        size: SanckBarSize
                                                            .MEDIUM));
                                              },
                                              icon: Icon(
                                                Icons.playlist_play,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color,
                                              )),
                                          IconButton(
                                              tooltip: "startRadio".tr,
                                              onPressed: () async {
                                                final songs = albumController
                                                    .songList
                                                    .toList();
                                                if (songs.isEmpty) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(snackbar(
                                                            context,
                                                            "radioNotAvailable"
                                                                .tr,
                                                            size: SanckBarSize
                                                                .MEDIUM));
                                                  }
                                                  return;
                                                }
                                                final ok = await playerController
                                                    .startRadio(songs.first);
                                                if (!context.mounted || ok) {
                                                  return;
                                                }
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(snackbar(
                                                        context,
                                                        "radioNotAvailable"
                                                            .tr,
                                                        size: SanckBarSize
                                                            .MEDIUM));
                                              },
                                              icon: Icon(
                                                Icons.sensors,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color,
                                              )),

                                          // Download button
                                          GetX<Downloader>(
                                              builder: (controller) {
                                            final id = albumController
                                                .album.value.browseId;
                                            return IconButton(
                                              tooltip: "downloadAlbumSongs".tr,
                                              onPressed: () {
                                                if (albumController
                                                    .isDownloaded.isTrue) {
                                                  return;
                                                }
                                                controller.downloadPlaylist(
                                                    id,
                                                    albumController.songList
                                                        .toList());
                                              },
                                              icon: albumController
                                                      .isDownloaded.isTrue
                                                  ? const Icon(
                                                      Icons.download_done)
                                                  : controller.playlistQueue
                                                              .containsKey(
                                                                  id) &&
                                                          controller
                                                                  .currentPlaylistId
                                                                  .toString() ==
                                                              id
                                                      ? Stack(
                                                          children: [
                                                            Center(
                                                                child: Text(
                                                                    "${controller.playlistDownloadingProgress.value}/${albumController.songList.length}",
                                                                    style: Theme.of(
                                                                            context)
                                                                        .textTheme
                                                                        .titleMedium!
                                                                        .copyWith(
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight:
                                                                                FontWeight.bold))),
                                                            const Center(
                                                                child:
                                                                    LoadingIndicator(
                                                              dimension: 30,
                                                            ))
                                                          ],
                                                        )
                                                      : controller.playlistQueue
                                                              .containsKey(id)
                                                          ? const Stack(
                                                              children: [
                                                                Center(
                                                                    child: Icon(
                                                                  Icons
                                                                      .hourglass_bottom,
                                                                  size: 20,
                                                                )),
                                                                Center(
                                                                    child:
                                                                        LoadingIndicator(
                                                                  dimension: 30,
                                                                ))
                                                              ],
                                                            )
                                                          : const Icon(
                                                              Icons.download),
                                            );
                                          }),

                                          // if (albumController
                                          //     .isAddedToLibrary.isTrue)
                                          //   IconButton(
                                          //       onPressed: () {
                                          //         albumController
                                          //             .syncPlaylistSongs();
                                          //       },
                                          //       icon: const Icon(
                                          //           Icons.cloud_sync)),

                                          IconButton(
                                              tooltip: "shareAlbum".tr,
                                              visualDensity:
                                                  const VisualDensity(
                                                      vertical: -3),
                                              splashRadius: 10,
                                              onPressed: () {
                                                Share.share(
                                                    "https://youtube.com/playlist?list=${albumController.album.value.audioPlaylistId}");
                                              },
                                              icon: const Icon(
                                                Icons.share,
                                                size: 20,
                                              )),
                                        ],
                                      )),
                                );
                              } else if (index == 1) {
                                return buildTitleSubTitle(
                                    context, albumController);
                              } else if (index == 2) {
                                return SizedBox(
                                    height: albumController.isSearchingOn.isTrue
                                        ? 60
                                        : 40,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 15.0, right: 10),
                                      child: Obx(
                                        () => SortWidget(
                                          tag: albumController
                                              .album.value.browseId,
                                          screenController: albumController,
                                          isSearchFeatureRequired: true,
                                          itemCountTitle:
                                              "${albumController.songList.length}",
                                          itemIcon: Icons.music_note,
                                          titleLeftPadding: 9,
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
                                    ));
                              } else if (albumController
                                      .isContentFetched.isFalse ||
                                  albumController.songList.isEmpty) {
                                return SizedBox(
                                  height: 300,
                                  child: Center(
                                    child:
                                        albumController.isContentFetched.isFalse
                                            ? const LoadingIndicator()
                                            : Text(
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
                                    const EdgeInsets.only(left: 20.0, right: 5),
                                child: SongListTile(
                                    onTap: () {
                                      playerController.playPlayListSong(
                                          List<MediaItem>.from(
                                              albumController.songList),
                                          index - 3,
                                          playfrom: PlaylingFrom(
                                              name: albumController
                                                  .album.value.title,
                                              type: PlaylingFromType.ALBUM));
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

  Widget buildTitleSubTitle(
      BuildContext context, AlbumScreenController albumController) {
    final album = albumController.album.value;
    final title = album.title;
    final description = album.description;
    final artists = album.artists?.map((e) => e['name']).join(", ") ?? "";
    return AnimatedBuilder(
      animation: albumController.animationController,
      builder: (context, child) {
        return SizedBox(
          height: albumController.heightAnimation.value,
          child: Transform.scale(
              scale: albumController.scaleAnimation.value, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0, bottom: 10, right: 20),
        child: Row(
          children: [
            InkWell(
              onTap: () {
                final songs = List<MediaItem>.from(albumController.songList);
                if (songs.isEmpty || !Get.isRegistered<PlayerController>()) {
                  return;
                }
                Get.find<PlayerController>().playPlayListSong(
                  songs,
                  0,
                  playfrom: PlaylingFrom(
                    name: album.title,
                    type: PlaylingFromType.ALBUM,
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ImageWidget(size: 72, album: album),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Marquee(
                    delay: const Duration(milliseconds: 300),
                    duration: const Duration(seconds: 5),
                    id: title.hashCode.toString(),
                    child: Text(
                      title.length > 50 ? title.substring(0, 50) : title,
                      maxLines: 1,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge!
                          .copyWith(fontSize: 22),
                    ),
                  ),
                  if ((description ?? '').isNotEmpty)
                    Text(
                      description!,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Marquee(
                      delay: const Duration(milliseconds: 300),
                      duration: const Duration(seconds: 5),
                      id: artists.hashCode.toString(),
                      child: Text(
                        artists,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
