import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/models/playling_from.dart';
import '/models/thumbnail.dart';
import '/services/podcast_service.dart';
import '/services/playlist_mix_service.dart';
import '../Podcasts/podcast_queue_screen.dart';
import '../Podcasts/podcasts_screen.dart';
import '/ui/widgets/playlist_album_scroll_behaviour.dart';
import '../../../services/downloader.dart';
import '../../navigator.dart';
import '../../player/player_controller.dart';
import '../../widgets/create_playlist_dialog.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/loader.dart';
import '../../widgets/mix_transition_chip.dart';
import '../../widgets/playlist_export_dialog.dart';
import '../../widgets/podcast_follow_button.dart';
import '../../widgets/podcast_play.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../../widgets/sort_widget.dart';
import '../Library/library_controller.dart';
import 'playlist_screen_controller.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tag = key.hashCode.toString();
    final playlistController =
        (Get.isRegistered<PlaylistScreenController>(tag: tag))
            ? Get.find<PlaylistScreenController>(tag: tag)
            : Get.put(PlaylistScreenController(), tag: tag);
    final size = MediaQuery.of(context).size;
    final playerController = Get.find<PlayerController>();
    final landscape = size.width > size.height;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          final scrollOffset = scrollInfo.metrics.pixels;

          if (landscape) {
            if (playlistController.scrollOffset.value != 0) {
              playlistController.scrollOffset.value = 0;
            }
          } else if ((playlistController.scrollOffset.value - scrollOffset)
                  .abs() >
              2) {
            // Throttle Opacity rebuilds while the hero parallax scrolls.
            playlistController.scrollOffset.value = scrollOffset;
          }
          if (scrollOffset > 270 || (landscape && scrollOffset > 215)) {
            playlistController.appBarTitleVisible.value = true;
          } else {
            playlistController.appBarTitleVisible.value = false;
          }
          return true;
        },
        child: Stack(
          children: [
            Obx(
              () => playlistController.isContentFetched.isTrue
                  ? Positioned(
                      top: landscape
                          ? 0
                          : -.25 * playlistController.scrollOffset.value,
                      right: landscape ? 0 : null,
                      child: Obx(() {
                        final opacityValue = 1 -
                            playlistController.scrollOffset.value /
                                (size.width - 100);
                        return Opacity(
                          opacity: opacityValue < 0 ||
                                  playlistController.isSearchingOn.isTrue &&
                                      !landscape
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
                              imageUrl: Thumbnail(playlistController
                                      .playlist.value.thumbnailUrl)
                                  .extraHigh,
                              fit: landscape ? BoxFit.fitHeight : BoxFit.cover,
                              width: landscape ? null : size.width,
                              height: landscape ? size.height : size.width,
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
                                imageUrl: playlistController
                                    .playlist.value.thumbnailUrl,
                                fit:
                                    landscape ? BoxFit.fitHeight : BoxFit.cover,
                                width: landscape ? null : size.width,
                                height: landscape ? size.height : size.width,
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
                            ),
                          ),
                        );
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
                              id: "${playlistController.playlist.value.title.hashCode.toString()}_appbar",
                              child: Text(
                                playlistController.appBarTitleVisible.isTrue
                                    ? playlistController.playlist.value.title
                                    : "",
                                maxLines: 1,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ),
                        ),
                        if (!playlistController
                                .playlist.value.isCloudPlaylist &&
                            playlistController.isDefaultPlaylist.isFalse)
                          SizedBox(
                            width: 50,
                            child: IconButton(
                                onPressed: () {
                                  showModalBottomSheet(
                                    constraints:
                                        const BoxConstraints(maxWidth: 500),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(10.0)),
                                    ),
                                    context: Get.find<PlayerController>()
                                        .homeScaffoldkey
                                        .currentState!
                                        .context,
                                    barrierColor:
                                        Colors.transparent.withAlpha(100),
                                    builder: (context) => SizedBox(
                                      height: 140,
                                      child: Column(
                                        children: [
                                          ListTile(
                                            leading: const Icon(Icons.edit),
                                            title: Text("renamePlaylist".tr),
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              showDialog(
                                                context: context,
                                                builder: (context) =>
                                                    CreateNRenamePlaylistPopup(
                                                        renamePlaylist: true,
                                                        playlist:
                                                            playlistController
                                                                .playlist
                                                                .value),
                                              );
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(Icons.delete),
                                            title: Text("removePlaylist".tr),
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              playlistController
                                                  .addNremoveFromLibrary(
                                                      playlistController
                                                          .playlist.value,
                                                      add: false)
                                                  .then((value) {
                                                Get.nestedKey(
                                                        ScreenNavigationSetup
                                                            .id)!
                                                    .currentState!
                                                    .pop();
                                                ScaffoldMessenger.of(
                                                        Get.context!)
                                                    .showSnackBar(snackbar(
                                                        Get.context!,
                                                        value
                                                            ? "playlistRemovedAlert"
                                                                .tr
                                                            : "operationFailed"
                                                                .tr,
                                                        size: SanckBarSize
                                                            .MEDIUM));
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.more_vert)),
                          )
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
                            addRepaintBoundaries: true,
                            padding: EdgeInsets.only(
                              top: playlistController.isSearchingOn.isTrue
                                  ? 0
                                  : landscape
                                      ? 150
                                      : 200,
                              bottom: 200,
                            ),
                            itemCount: playlistController.songList.isEmpty ||
                                    playlistController.isContentFetched.isFalse
                                ? 4
                                : playlistController.songList.length + 3,
                            itemBuilder: (_, index) {
                              if (index == 0) {
                                // Podcasts / YT channels: no music action strip
                                // (play/shuffle/download/…). Follow lives under
                                // the title in the header row (index == 1).
                                final pl0 =
                                    playlistController.playlist.value;
                                final isPodcastPage = pl0.kind == 'podcast' ||
                                    pl0.kind == 'yt_channel' ||
                                    pl0.playlistId.startsWith('MPSP') ||
                                    RegExp(r'^UC[\w-]{20,}$')
                                        .hasMatch(pl0.playlistId);
                                if (isPodcastPage) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(left: 15.0),
                                  child: SizedBox(
                                    height: 40,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          // Bookmark — playlists only. Podcasts
                                          // use the green Follow pill under the title.
                                          Obx(() {
                                            final pl = playlistController
                                                .playlist.value;
                                            final isPodcast =
                                                pl.kind == 'podcast' ||
                                                    pl.playlistId
                                                        .startsWith('MPSP') ||
                                                    pl.kind == 'yt_channel';
                                            if (isPodcast ||
                                                pl.isPipedPlaylist ||
                                                !pl.isCloudPlaylist) {
                                              return const SizedBox.shrink();
                                            }
                                            return IconButton(
                                                tooltip: playlistController
                                                        .isAddedToLibrary
                                                        .isFalse
                                                    ? "addToLibrary".tr
                                                    : "removeFromLibrary".tr,
                                                splashRadius: 10,
                                                onPressed: () {
                                                  final add = playlistController
                                                      .isAddedToLibrary.isFalse;
                                                  playlistController
                                                      .addNremoveFromLibrary(
                                                          playlistController
                                                              .playlist.value,
                                                          add: add)
                                                      .then((value) {
                                                    if (!context.mounted) {
                                                      return;
                                                    }

                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(snackbar(
                                                            context,
                                                            value
                                                                ? add
                                                                    ? "playlistBookmarkAddAlert"
                                                                        .tr
                                                                    : "listBookmarkRemoveAlert"
                                                                        .tr
                                                                : "operationFailed"
                                                                    .tr,
                                                            size: SanckBarSize
                                                                .MEDIUM));
                                                  });
                                                },
                                                icon: Icon(playlistController
                                                        .isAddedToLibrary
                                                        .isFalse
                                                    ? Icons.bookmark_add
                                                    : Icons.bookmark_added));
                                          }),
                                          // Play button
                                          IconButton(
                                              tooltip: "play".tr,
                                              onPressed: () {
                                                _playPlaylistFrom(
                                                  playerController,
                                                  playlistController,
                                                  0,
                                                );
                                              },
                                              icon: Icon(
                                                Icons.play_circle,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color,
                                              )),
                                          // Enqueue button
                                          IconButton(
                                              tooltip: "enqueueSongs".tr,
                                              onPressed: () async {
                                                final ok =
                                                    await Get.find<
                                                            PlayerController>()
                                                        .enqueueSongList(
                                                            playlistController
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
                                                        playlistController
                                                            .songList
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
                                              onPressed: () {
                                                final songs =
                                                    playlistController.songList
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
                                                playerController
                                                    .startRadio(songs.first);
                                              },
                                              icon: Icon(
                                                Icons.sensors,
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
                                                        playlistController
                                                            .songList);
                                                songsToplay.shuffle();
                                                songsToplay.shuffle();
                                                if (Get.isRegistered<
                                                    PlaylistMixService>()) {
                                                  Get.find<PlaylistMixService>()
                                                      .deactivatePlayback();
                                                }
                                                playerController.playPlayListSong(
                                                    songsToplay, 0,
                                                    playfrom: PlaylingFrom(
                                                        name: playlistController
                                                            .playlist
                                                            .value
                                                            .title,
                                                        type: PlaylingFromType
                                                            .PLAYLIST));
                                              },
                                              icon: Icon(
                                                Icons.shuffle,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color,
                                              )),
                                          // Mix mode toggle — icon-only to match
                                          // the rest of the action row.
                                          Obx(() {
                                            final pl =
                                                playlistController.playlist.value;
                                            final isPodcast =
                                                pl.kind == 'podcast' ||
                                                    pl.playlistId
                                                        .startsWith('MPSP');
                                            if (isPodcast) {
                                              return const SizedBox.shrink();
                                            }
                                            final on =
                                                playlistController.isMixMode.isTrue;
                                            final color = on
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Theme.of(context)
                                                    .textTheme
                                                    .titleMedium!
                                                    .color;
                                            return IconButton(
                                              tooltip: 'mix'.tr,
                                              onPressed: () {
                                                playlistController
                                                    .toggleMixMode();
                                              },
                                              icon: Icon(
                                                Icons.tune,
                                                color: color,
                                              ),
                                            );
                                          }),
                                          Obx(() {
                                            if (playlistController
                                                    .isMixMode.isFalse ||
                                                playlistController
                                                    .isAnalyzingMix.isFalse) {
                                              return const SizedBox.shrink();
                                            }
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 4, right: 8),
                                              child: SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  value: playlistController
                                                              .mixAnalyzeProgress
                                                              .value >
                                                          0
                                                      ? playlistController
                                                          .mixAnalyzeProgress
                                                          .value
                                                      : null,
                                                ),
                                              ),
                                            );
                                          }),
                                          Obx(() {
                                            if (playlistController
                                                .isMixMode.isFalse) {
                                              return const SizedBox.shrink();
                                            }
                                            return IconButton(
                                              tooltip: 'mixSmartOrder'.tr,
                                              onPressed: () async {
                                                await playlistController
                                                    .smartOrderForMix();
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(snackbar(
                                                          context,
                                                          'mixSmartOrderDone'
                                                              .tr,
                                                          size: SanckBarSize
                                                              .MEDIUM));
                                                }
                                              },
                                              icon: const Icon(
                                                  Icons.auto_awesome),
                                            );
                                          }),
                                          // Download button
                                          GetX<Downloader>(
                                              builder: (controller) {
                                            final id = playlistController
                                                .playlist.value.playlistId;
                                            return IconButton(
                                              tooltip: "downloadPlaylist".tr,
                                              onPressed: () {
                                                if (playlistController
                                                    .isDownloaded.isTrue) {
                                                  return;
                                                }
                                                controller.downloadPlaylist(
                                                    id,
                                                    playlistController.songList
                                                        .toList());
                                              },
                                              icon: playlistController
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
                                                                    "${controller.playlistDownloadingProgress.value}/${playlistController.songList.length}",
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

                                          if (playlistController
                                              .isAddedToLibrary.isTrue)
                                            IconButton(
                                                tooltip: "syncPlaylistSongs".tr,
                                                onPressed: () {
                                                  playlistController
                                                      .syncPlaylistSongs();
                                                },
                                                icon: const Icon(
                                                    Icons.cloud_sync)),
                                          if (playlistController
                                              .playlist.value.isPipedPlaylist)
                                            IconButton(
                                                tooltip:
                                                    "blacklistPipedPlaylist".tr,
                                                icon: const Icon(
                                                  Icons.block,
                                                  size: 20,
                                                ),
                                                splashRadius: 10,
                                                onPressed: () {
                                                  Get.nestedKey(
                                                          ScreenNavigationSetup
                                                              .id)!
                                                      .currentState!
                                                      .pop();
                                                  Get.find<
                                                          LibraryPlaylistsController>()
                                                      .blacklistPipedPlaylist(
                                                          playlistController
                                                              .playlist.value);
                                                  ScaffoldMessenger.of(
                                                          Get.context!)
                                                      .showSnackBar(snackbar(
                                                          Get.context!,
                                                          "playlistBlacklistAlert"
                                                              .tr,
                                                          size: SanckBarSize
                                                              .MEDIUM));
                                                }),
                                          if (playlistController
                                              .playlist.value.isCloudPlaylist)
                                            IconButton(
                                              tooltip: "sharePlaylist".tr,
                                              visualDensity:
                                                  const VisualDensity(
                                                vertical: -3,
                                              ),
                                              splashRadius: 10,
                                              onPressed: () {
                                                final content =
                                                    playlistController
                                                        .playlist.value;
                                                if (content.isPipedPlaylist) {
                                                  Share.share(
                                                      "https://piped.video/playlist?list=${content.playlistId}");
                                                } else {
                                                  final isPlaylistIdPrefixAvlbl =
                                                      content.playlistId
                                                              .substring(
                                                                  0, 2) ==
                                                          "VL";
                                                  String url =
                                                      "https://youtube.com/playlist?list=";

                                                  url = isPlaylistIdPrefixAvlbl
                                                      ? url +
                                                          content.playlistId
                                                              .substring(2)
                                                      : url +
                                                          content.playlistId;
                                                  Share.share(url);
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.share,
                                                size: 20,
                                              ),
                                            ),
                                          // Export button - opens export dialog
                                          IconButton(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (dialogContext) =>
                                                    PlaylistExportDialog(
                                                  controller:
                                                      playlistController,
                                                  parentContext: context,
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.file_upload),
                                            tooltip: "exportPlaylist".tr,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              } else if (index == 1) {
                                final pl = playlistController.playlist.value;
                                final title = pl.title;
                                final description = pl.description;
                                final isPodcast = pl.kind == 'podcast' ||
                                    pl.playlistId.startsWith('MPSP') ||
                                    pl.kind == 'yt_channel' ||
                                    RegExp(r'^UC[\w-]{20,}$')
                                        .hasMatch(pl.playlistId);

                                return AnimatedBuilder(
                                  animation:
                                      playlistController.animationController,
                                  builder: (context, child) {
                                    // Podcasts need room for the Follow pill
                                    // under the title (image-2 style header).
                                    final base =
                                        playlistController.heightAnimation.value;
                                    final height = isPodcast
                                        ? 10 +
                                            ((base - 10) / 70).clamp(0.0, 1.0) *
                                                110
                                        : base;
                                    return SizedBox(
                                      height: height,
                                      child: Transform.scale(
                                        scale: playlistController
                                            .scaleAnimation.value,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        left: 20.0, bottom: 10, right: 20),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Explicit cover so the title row always
                                        // shows art (not a generic icon) even when
                                        // the blurred hero background fails.
                                        InkWell(
                                          onTap: () {
                                            if (playlistController
                                                .songList.isEmpty) {
                                              return;
                                            }
                                            _playPlaylistFrom(
                                              playerController,
                                              playlistController,
                                              0,
                                            );
                                          },
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: ImageWidget(
                                              size: 64,
                                              playlist: pl,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Marquee(
                                                delay: const Duration(
                                                    milliseconds: 300),
                                                duration:
                                                    const Duration(seconds: 5),
                                                id: title.hashCode.toString(),
                                                child: Text(
                                                  title.length > 50
                                                      ? title.substring(0, 50)
                                                      : title,
                                                  maxLines: 1,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge!
                                                      .copyWith(fontSize: 22),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4.0),
                                                child: Marquee(
                                                  delay: const Duration(
                                                      milliseconds: 300),
                                                  duration: const Duration(
                                                      seconds: 5),
                                                  id: description.hashCode
                                                      .toString(),
                                                  child: Text(
                                                    isPodcast
                                                        ? (description ??
                                                            "podcasts".tr)
                                                        : (description ??
                                                            "playlist".tr),
                                                    maxLines: 1,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                ),
                                              ),
                                              if (isPodcast) ...[
                                                const SizedBox(height: 8),
                                                Obx(() => PodcastFollowButton(
                                                      following:
                                                          playlistController
                                                              .isAddedToLibrary
                                                              .isTrue,
                                                      onPressed: () {
                                                        final add =
                                                            playlistController
                                                                .isAddedToLibrary
                                                                .isFalse;
                                                        playlistController
                                                            .addNremoveFromLibrary(
                                                                playlistController
                                                                    .playlist
                                                                    .value,
                                                                add: add)
                                                            .then((value) {
                                                          if (!context
                                                              .mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                                  snackbar(
                                                            context,
                                                            !value
                                                                ? 'operationFailed'
                                                                    .tr
                                                                : add
                                                                    ? 'subscribedAsPodcast'
                                                                        .tr
                                                                    : 'removeFromLib'
                                                                        .tr,
                                                            size: SanckBarSize
                                                                .MEDIUM,
                                                          ));
                                                        });
                                                      },
                                                    )),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } else if (index == 2) {
                                return SizedBox(
                                    height:
                                        playlistController.isSearchingOn.isTrue
                                            ? 60
                                            : 40,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 15.0, right: 10),
                                      child: Obx(
                                        () => SortWidget(
                                          tag: playlistController
                                              .playlist.value.playlistId,
                                          screenController: playlistController,
                                          isSearchFeatureRequired: true,
                                          isPlaylistRearrageFeatureRequired: !playlistController
                                                  .playlist
                                                  .value
                                                  .isCloudPlaylist &&
                                              playlistController.playlist.value
                                                      .playlistId !=
                                                  "LIBRP" &&
                                              playlistController.playlist.value
                                                      .playlistId !=
                                                  "SongDownloads" &&
                                              playlistController.playlist.value
                                                      .playlistId !=
                                                  "SongsCache",
                                          isSongDeletetioFeatureRequired:
                                              !playlistController.playlist.value
                                                  .isCloudPlaylist,
                                          itemCountTitle:
                                              "${playlistController.songList.length}",
                                          itemIcon: Icons.music_note,
                                          titleLeftPadding: 9,
                                          requiredSortTypes:
                                              buildSortTypeSet(false, true),
                                          onSort: playlistController.onSort,
                                          onSearch: playlistController.onSearch,
                                          onSearchClose:
                                              playlistController.onSearchClose,
                                          onSearchStart:
                                              playlistController.onSearchStart,
                                          startAdditionalOperation:
                                              playlistController
                                                  .startAdditionalOperation,
                                          selectAll:
                                              playlistController.selectAll,
                                          performAdditionalOperation:
                                              playlistController
                                                  .performAdditionalOperation,
                                          cancelAdditionalOperation:
                                              playlistController
                                                  .cancelAdditionalOperation,
                                        ),
                                      ),
                                    ));
                              } else if (playlistController
                                      .isContentFetched.isFalse ||
                                  playlistController.songList.isEmpty) {
                                return SizedBox(
                                  height: 300,
                                  child: Center(
                                    child: playlistController
                                            .isContentFetched.isFalse
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

                              final pl = playlistController.playlist.value;
                              final isPodcastList = pl.kind == 'podcast' ||
                                  pl.kind == 'yt_channel' ||
                                  pl.playlistId.startsWith('MPSP') ||
                                  RegExp(r'^UC[\w-]{20,}$')
                                      .hasMatch(pl.playlistId);
                              final song =
                                  playlistController.songList[index - 3];
                              final songIndex = index - 3;
                              void playThis() {
                                _playPlaylistFrom(
                                  playerController,
                                  playlistController,
                                  songIndex,
                                );
                              }
                              // Podcast episodes get an AntennaPod-style row
                              // (date · 2-line title · duration), not the
                              // scrolling music tile.
                              if (isPodcastList) {
                                return _PodcastEpisodeTile(
                                    song: song, onTap: playThis);
                              }
                              return Obx(() {
                                final mixOn =
                                    playlistController.isMixMode.isTrue;
                                final analysis =
                                    playlistController.mixAnalyses[song.id];
                                final isLast = songIndex >=
                                    playlistController.songList.length - 1;
                                final gapStyle = mixOn && !isLast
                                    ? playlistController
                                        .transitionForGap(songIndex)
                                    : null;
                                return Padding(
                                  padding: const EdgeInsets.only(
                                      left: 20.0, right: 5),
                                  child: Column(
                                    children: [
                                      SongListTile(
                                        onTap: playThis,
                                        song: song,
                                        isPlaylistOrAlbum: true,
                                        playlist: pl,
                                        showMixMeta: mixOn,
                                        mixAnalysis: analysis,
                                      ),
                                      if (mixOn &&
                                          gapStyle != null &&
                                          !isLast)
                                        MixTransitionChip(
                                          style: gapStyle,
                                          onTap: () async {
                                            final picked =
                                                await showMixTransitionPicker(
                                                    context, gapStyle);
                                            if (picked != null) {
                                              await playlistController
                                                  .setTransitionForGap(
                                                      songIndex, picked);
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                );
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Pinned "Similar podcasts" panel — reserved at the bottom of
                // the screen (does not scroll away). Only for podcasts opened
                // from search.
                Obx(() {
                  final pl = playlistController.playlist.value;
                  final isPodcastList = pl.kind == 'podcast' ||
                      pl.kind == 'yt_channel' ||
                      pl.playlistId.startsWith('MPSP') ||
                      RegExp(r'^UC[\w-]{20,}$').hasMatch(pl.playlistId);
                  if (!playlistController.showSimilarPodcasts.value ||
                      !isPodcastList) {
                    return const SizedBox.shrink();
                  }
                  return _PodcastSimilarFooter(title: pl.title);
                }),
              ],
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

void _playPlaylistFrom(
  PlayerController playerController,
  PlaylistScreenController playlistController,
  int index,
) {
  final pl = playlistController.playlist.value;
  final mixOn = playlistController.isMixMode.isTrue;
  if (Get.isRegistered<PlaylistMixService>()) {
    final mix = Get.find<PlaylistMixService>();
    if (mixOn) {
      mix.activatePlayback(
        enabled: true,
        playlistId: pl.playlistId,
        startIndex: index,
        style: playlistController.transitionForGap(index),
      );
    } else {
      mix.deactivatePlayback();
    }
  }
  playerController.playPlayListSong(
    List<MediaItem>.from(playlistController.songList),
    index,
    playfrom: PlaylingFrom(
      name: pl.title,
      type: PlaylingFromType.PLAYLIST,
    ),
  );
}

/// AntennaPod-style episode row: 56×56 art, a publish-date meta line, a 2-line
/// (non-scrolling) bold title and the duration. Used for podcast episodes in
/// place of the music SongListTile. YouTube episodes carry no file size, so the
/// meta line is just the date.
class _PodcastEpisodeTile extends StatelessWidget {
  const _PodcastEpisodeTile({required this.song, required this.onTap});
  final MediaItem song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = (song.extras?['date'] ?? '').toString().trim();
    final durationSec = song.duration?.inSeconds ?? 0;
    final durationText = durationSec > 0
        ? PodcastService.formatDuration(durationSec)
        : (song.extras?['length'] ?? '').toString().trim();
    final art = Thumbnail(song.artUri?.toString() ?? '').medium;
    return InkWell(
      onTap: onTap,
      onLongPress: () => showAddToQueueSheet(context, song),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
            child: Row(
              // Outer row centers the play icon vertically; the art+text block
              // inside stays top-aligned.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: art,
                          width: 56,
                          height: 56,
                          memCacheWidth:
                              (56 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.podcasts, size: 40),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (date.isNotEmpty)
                              Text(
                                date,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (durationText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  durationText,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_circle_outline, size: 30),
              ],
            ),
          ),
          const Divider(height: 1, indent: 20, endIndent: 12),
        ],
      ),
    );
  }
}

/// "Similar podcasts" horizontal strip shown under the episode list on a
/// podcast show page. Sourced from Apple's genre charts (PodcastService.similar)
/// keyed off the current show's title. Tapping a card opens that podcast's
/// episode list. Renders nothing while loading or when no matches are found.
class _PodcastSimilarFooter extends StatefulWidget {
  const _PodcastSimilarFooter({required this.title});
  final String title;

  @override
  State<_PodcastSimilarFooter> createState() => _PodcastSimilarFooterState();
}

class _PodcastSimilarFooterState extends State<_PodcastSimilarFooter> {
  List<Map<String, dynamic>> _similar = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await PodcastService.similar(widget.title);
      if (!mounted) return;
      setState(() {
        _similar = res;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Once we know there are no matches, don't reserve space.
    if (!_loading && _similar.isEmpty) return const SizedBox.shrink();
    // Lift the panel above the minimized player bar so nothing is hidden.
    final playerMin =
        Get.find<PlayerController>().playerPanelMinHeight.value;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withOpacity(0.4)),
        ),
      ),
      padding: EdgeInsets.only(top: 8, bottom: playerMin + 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              "similarPodcasts".tr,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            height: 96,
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _similar.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final p = _similar[i];
                      final art =
                          Thumbnail((p['artwork'] ?? '').toString()).medium;
                      const tile = 64.0;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          if (shouldPlayPodcastShowOnTap()) {
                            final ok = await playPodcastShow(p);
                            if (ok) return;
                          }
                          Get.to(() => PodcastEpisodesScreen(podcast: p));
                        },
                        child: SizedBox(
                          width: tile,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: art,
                                  width: tile,
                                  height: tile,
                                  memCacheWidth:
                                      (tile * MediaQuery.devicePixelRatioOf(context))
                                          .round(),
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    width: tile,
                                    height: tile,
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.podcasts, size: 22),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (p['title'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w500, height: 1.1),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
