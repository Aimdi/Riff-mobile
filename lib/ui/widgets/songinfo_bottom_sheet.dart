import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/wizestream_service.dart';

import '../../models/media_item_extras.dart';
import '../../services/ban_service.dart';
import '../../services/discovery/discovery_service.dart';
import '../../utils/hive_boxes.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '/utils/helper.dart';
import '/services/piped_service.dart';
import '/ui/widgets/sleep_timer_bottom_sheet.dart';
import '/ui/player/player_controller.dart';
import '../screens/Library/library_controller.dart';
import '/ui/widgets/add_to_playlist.dart';
import '/ui/widgets/favorite_heart_button.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/utils/sheet_insets.dart';
import '/utils/content_filters.dart';
import '../../models/playlist.dart';
import '../navigator.dart';
import 'discovery/similar_songs_sheet.dart';
import 'song_download_btn.dart';
import 'image_widget.dart';
import 'riff_sheet.dart';
import '../screens/Home/home_layout.dart';
import 'song_info_dialog.dart';

/// Player / mini-player long-press — same sheet as the full player.
void showCurrentSongSheet({
  required MediaItem? song,
  BuildContext? context,
}) {
  final player = Get.isRegistered<PlayerController>()
      ? Get.find<PlayerController>()
      : null;
  final sheetContext =
      context ?? player?.homeScaffoldkey.currentContext ?? Get.context;
  if (sheetContext == null || song == null) return;
  showModalBottomSheet(
    useRootNavigator: true,
    constraints: const BoxConstraints(maxWidth: 500),
    shape: riffSheetShape,
    isScrollControlled: true,
    context: sheetContext,
    barrierColor: Colors.transparent.withAlpha(100),
    builder: (context) => SongInfoBottomSheet(
      song,
      calledFromPlayer: true,
    ),
  ).whenComplete(() => Get.delete<SongInfoController>());
}

class SongInfoBottomSheet extends StatelessWidget {
  const SongInfoBottomSheet(this.song,
      {super.key,
      this.playlist,
      this.calledFromPlayer = false,
      this.calledFromQueue = false});
  final MediaItem song;
  final Playlist? playlist;
  final bool calledFromPlayer;
  final bool calledFromQueue;

  /// Reuses the sheet's controller across rebuilds (Get.put in build used to
  /// construct — and run the Hive lookups of — a throwaway controller every
  /// time). A leftover controller for another song is replaced, so a new
  /// sheet always shows fresh data.
  static SongInfoController _controllerFor(
      MediaItem song, bool calledFromPlayer) {
    if (Get.isRegistered<SongInfoController>()) {
      final existing = Get.find<SongInfoController>();
      if (existing.song.id == song.id &&
          existing.calledFromPlayer == calledFromPlayer) {
        return existing;
      }
      Get.delete<SongInfoController>(force: true);
    }
    return Get.put(SongInfoController(song, calledFromPlayer));
  }

  @override
  Widget build(BuildContext context) {
    final songInfoController = _controllerFor(song, calledFromPlayer);
    final playerController = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color;
    final hasAlbum =
        ((song.extras?['album'] as Map?)?['id'] ?? '').toString().isNotEmpty;
    final inEditablePlaylist = (playlist != null &&
            !playlist!.isCloudPlaylist &&
            !(playlist!.playlistId == "LIBRP")) ||
        (playlist != null && playlist!.isPipedPlaylist);

    void snack(String text, {SanckBarSize size = SanckBarSize.MEDIUM}) {
      final ctx = Get.context;
      if (ctx == null || !ctx.mounted) return;
      ScaffoldMessenger.of(ctx)
          .showSnackBar(snackbar(ctx, text, size: size));
    }

    return Padding(
      // Callers should use useRootNavigator: true so the sheet clears the
      // mini player; keep system safe-area inset here.
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context, liftAboveMiniPlayer: false) + 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            // Song header: tap plays it (or shows its details if it is
            // already playing).
            InkWell(
              onTap: () async {
                if (Get.isRegistered<PlayerController>() &&
                    playerController.currentSong.value?.id != song.id) {
                  final ok = await playerController.playPlayListSong([song], 0);
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.of(context).maybePop();
                  } else {
                    snackOperationFailed(context);
                  }
                  return;
                }
                showDialog(
                  context: context,
                  builder: (context) => SongInfoDialog(song: song),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 10, 10),
                child: Row(
                  children: [
                    ImageWidget(song: song, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 17,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: fg)),
                          const SizedBox(height: 3),
                          Text(song.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: homeCardSubtitleStyle(context)),
                        ],
                      ),
                    ),
                    calledFromPlayer
                        ? IconButton(
                            tooltip: 'songInfo'.tr,
                            onPressed: () => showDialog(
                                  context: context,
                                  builder: (context) =>
                                      SongInfoDialog(song: song),
                                ),
                            icon: Icon(Icons.info_outline_rounded, color: fg))
                        : FavoriteHeartButton(
                            isFav: songInfoController.isCurrentSongFav,
                            onToggleFav: songInfoController.toggleFav,
                            song: () => song,
                          ),
                    SongDownloadButton(
                      song_: song,
                      isDownloadingDoneCallback:
                          songInfoController.setDownloadStatus,
                    ),
                  ],
                ),
              ),
            ),
            RiffQuickActions([
              RiffQuickAction(
                icon: Icons.sensors_rounded,
                label: 'startRadio'.tr,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await playerController.startRadio(song);
                  if (!ok) snack("radioNotAvailable".tr);
                },
              ),
              if (!calledFromQueue)
                RiffQuickAction(
                  icon: Icons.playlist_play_rounded,
                  label: 'playNext'.tr,
                  onTap: () async {
                    Navigator.of(context).pop();
                    final ok = await playerController.playNext(song);
                    snack(
                        ok
                            ? "${"playnextMsg".tr} ${song.title}"
                            : "operationFailed".tr,
                        size: SanckBarSize.BIG);
                  },
                ),
              RiffQuickAction(
                icon: Icons.playlist_add_rounded,
                label: 'addToPlaylist'.tr,
                onTap: () {
                  Navigator.of(context).pop();
                  showAddToPlaylistSheet(context, [song]);
                },
              ),
              RiffQuickAction(
                icon: Icons.ios_share_rounded,
                label: 'share'.tr,
                onTap: () => Share.share(SongLinkShare.shareText(song)),
              ),
            ]),
            const SizedBox(height: 6),
            RiffSheetTile(
              icon: Icons.graphic_eq_rounded,
              title: "similarSongs".tr,
              onTap: () {
                Navigator.of(context).pop();
                showModalBottomSheet(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  constraints: const BoxConstraints(maxWidth: 500),
                  shape: riffSheetShape,
                  builder: (context) => SimilarSongsSheet(seed: song),
                );
              },
            ),
            RiffSheetTile(
              icon: Icons.queue_music_rounded,
              title: "moreLikeThisPlayNext".tr,
              onTap: () {
                Navigator.of(context).pop();
                playerController.moreLikeThisPlayNext(song);
              },
            ),
            if (!(calledFromPlayer || calledFromQueue))
              RiffSheetTile(
                icon: Icons.low_priority_rounded,
                title: "enqueueSong".tr,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await playerController.enqueueSong(song);
                  snack(ok ? "songEnqueueAlert".tr : "operationFailed".tr);
                },
              ),
            // Only when there is an album id to open: YouTube often sends
            // an album name with a null id.
            if (hasAlbum)
              RiffSheetTile(
                icon: Icons.album_outlined,
                title: "goToAlbum".tr,
                onTap: () {
                  Navigator.of(context).pop();
                  if (calledFromPlayer || calledFromQueue) {
                    playerController.playerPanelController.close();
                  }
                  Get.toNamed(ScreenNavigationSetup.albumScreen,
                      id: ScreenNavigationSetup.id,
                      arguments: (
                        null,
                        (song.extras!['album'] as Map)['id'].toString()
                      ));
                },
              ),
            ...artistWidgetList(song, context),
            const RiffSheetDivider(),
            if (inEditablePlaylist)
              RiffSheetTile(
                icon: Icons.remove_circle_outline_rounded,
                title: playlist!.title == "Library Songs"
                    ? "removeFromLib".tr
                    : "removeFromPlaylist".tr,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await songInfoController.removeSongFromPlaylist(
                      song, playlist!);
                  snack(ok
                      ? "${"songRemovedAlert".tr} ${playlist!.title}"
                      : "operationFailed".tr);
                },
              ),
            if (calledFromQueue)
              RiffSheetTile(
                icon: Icons.remove_circle_outline_rounded,
                title: "removeFromQueue".tr,
                onTap: () {
                  Navigator.of(context).pop();
                  if (playerController.currentSong.value?.id == song.id) {
                    snack("songRemovedfromQueueCurrSong".tr,
                        size: SanckBarSize.BIG);
                  } else {
                    final ok = playerController.removeFromQueue(song);
                    snack(ok
                        ? "songRemovedfromQueue".tr
                        : "operationFailed".tr);
                  }
                },
              ),
            Obx(
              () => (songInfoController.isDownloaded.isTrue &&
                      (playlist?.playlistId != "SongDownloads" &&
                          playlist?.playlistId != "SongsCache"))
                  ? RiffSheetTile(
                      icon: Icons.delete_outline_rounded,
                      title: "deleteDownloadData".tr,
                      onTap: () {
                        Navigator.of(context).pop();
                        final box = Hive.box("SongDownloads");
                        Get.find<LibrarySongsController>()
                            .removeSong(song, true,
                                url: box.get(song.id)['url'])
                            .then((ok) async {
                          if (!ok) {
                            snack("operationFailed".tr,
                                size: SanckBarSize.BIG);
                            return;
                          }
                          box.delete(song.id).then((value) {
                            final tag = Key(playlist?.playlistId ?? '')
                                .hashCode
                                .toString();
                            if (playlist != null &&
                                Get.isRegistered<PlaylistScreenController>(
                                    tag: tag)) {
                              Get.find<PlaylistScreenController>(tag: tag)
                                  .checkDownloadStatus();
                            }
                            snack("deleteDownloadedDataAlert".tr,
                                size: SanckBarSize.BIG);
                          });
                        });
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            RiffSheetTile(
              icon: Icons.bedtime_outlined,
              title: "sleepTimer".tr,
              onTap: () {
                Navigator.of(context).pop();
                final sheetContext =
                    playerController.homeScaffoldkey.currentContext ??
                        Get.context;
                showSleepTimerSheet(sheetContext);
              },
            ),
            // Open in YouTube / YouTube Music / WizeStream.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Text("openIn".tr,
                  style: homeCardSubtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  RiffChoiceChip(
                    icon: Ionicons.logo_youtube,
                    label: 'YouTube',
                    onTap: () => launchUrl(
                        Uri.parse("https://youtube.com/watch?v=${song.id}")),
                  ),
                  RiffChoiceChip(
                    icon: Ionicons.play_circle,
                    label: 'YouTube Music',
                    onTap: () => launchUrl(Uri.parse(
                        "https://music.youtube.com/watch?v=${song.id}")),
                  ),
                  if (WizeStream.isInstalled &&
                      WizeStream.watchUrlFor(song) != null)
                    RiffChoiceChip(
                      icon: Icons.smart_display_outlined,
                      label: 'WizeStream',
                      onTap: () =>
                          WizeStream.open(WizeStream.watchUrlFor(song)!),
                    ),
                ],
              ),
            ),
            const RiffSheetDivider(),
            RiffSheetTile(
              icon: Icons.block_rounded,
              title: "neverPlayThis".tr,
              destructive: true,
              onTap: () async {
                Navigator.of(context).pop();
                final ok = await BanService.ban(song);
                if (ok && Get.isRegistered<DiscoveryService>()) {
                  Get.find<DiscoveryService>().onNeverPlay(song);
                }
                snack(
                    ok
                        ? "${"songBannedMsg".tr} ${song.title}"
                        : "operationFailed".tr,
                    size: SanckBarSize.BIG);
              },
            ),
            if (BanService.primaryArtist(song) case final artist?)
              RiffSheetTile(
                icon: Icons.person_off_outlined,
                title: "neverPlayArtist".tr,
                subtitle: artist,
                destructive: true,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await BanService.banArtist(artist);
                  snack(
                      ok
                          ? "${"artistBannedMsg".tr} $artist"
                          : "operationFailed".tr,
                      size: SanckBarSize.BIG);
                },
              ),
            if (_albumOf(song) case final album?)
              RiffSheetTile(
                icon: Icons.album_outlined,
                title: "neverPlayAlbum".tr,
                subtitle: album.name,
                destructive: true,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await BanService.banCollection(
                      album.id, album.name, "album");
                  snack(
                      ok
                          ? "${"collectionBannedMsg".tr} ${album.name}"
                          : "operationFailed".tr,
                      size: SanckBarSize.BIG);
                },
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> artistWidgetList(MediaItem song, BuildContext context) {
    final artistList = [];
    final artists = song.extras?['artists'];
    if (artists is List) {
      for (dynamic each in artists) {
        if (each is Map && each['id'] != null) artistList.add(each);
      }
    }
    return [
      for (final e in artistList)
        RiffSheetTile(
          icon: Icons.person_outline_rounded,
          title: "${"viewArtist".tr} · ${e['name']}",
          onTap: () async {
            Navigator.of(context).pop();
            if (calledFromPlayer || calledFromQueue) {
              Get.find<PlayerController>().playerPanelController.close();
            }
            await Get.toNamed(ScreenNavigationSetup.artistScreen,
                id: ScreenNavigationSetup.id,
                preventDuplicates: true,
                arguments: [true, e['id']]);
          },
        ),
    ];
  }
}

class SongInfoController extends GetxController
    with RemoveSongFromPlaylistMixin {
  final isCurrentSongFav = false.obs;
  final MediaItem song;
  final bool calledFromPlayer;
  List artistList = [].obs;
  final isDownloaded = false.obs;
  SongInfoController(this.song, this.calledFromPlayer) {
    _setInitStatus(song);
  }
  _setInitStatus(MediaItem song) async {
    isDownloaded.value =
        HiveBoxes.songDownloadsSync()?.containsKey(song.id) ?? false;
    isCurrentSongFav.value = (await HiveBoxes.fav()).containsKey(song.id);
    for (final each in song.extrasArtists) {
      if (each['id'] != null) artistList.add(each);
    }
  }

  void setDownloadStatus(bool isDownloaded_) {
    if (isDownloaded_) {
      Future.delayed(const Duration(milliseconds: 100),
          () => isDownloaded.value = isDownloaded_);
    }
  }

  Future<void> toggleFav() async {
    if (!Get.isRegistered<PlayerController>()) return;
    final adding = isCurrentSongFav.isFalse;
    await Get.find<PlayerController>().toggleFavouriteFor(song, adding: adding);
    isCurrentSongFav.value = adding;
  }
}

mixin RemoveSongFromPlaylistMixin {
  Future<bool> removeSongFromPlaylist(MediaItem item, Playlist playlist) async {
    final box = await Hive.openBox(playlist.playlistId);
    //Library songs case
    if (playlist.playlistId == "SongsCache") {
      if (!box.containsKey(item.id)) {
        Hive.box("SongDownloads").delete(item.id);
        Get.find<LibrarySongsController>().removeSong(item, true);
      } else {
        Get.find<LibrarySongsController>().removeSong(item, false);
        box.delete(item.id);
      }
    } else if (playlist.playlistId == "SongDownloads") {
      box.delete(item.id);
      Get.find<LibrarySongsController>().removeSong(item, true);
    } else if (!playlist.isPipedPlaylist) {
      //Other playlist song case
      final index = box.values
          .toList()
          .indexWhere((ele) => ele is Map && ele['videoId'] == item.id);
      if (index >= 0) await box.deleteAt(index);
    }

    // this try catch block is to handle the case when song is removed from libsongs sections
    try {
      final plstCntroller = Get.find<PlaylistScreenController>(
          tag: Key(playlist.playlistId).hashCode.toString());
      if (playlist.isPipedPlaylist) {
        final res = await Get.find<PipedServices>()
            .getPlaylistSongs(playlist.playlistId);
        final songIndex = res.indexWhere((element) => element.id == item.id);
        if (songIndex != -1) {
          final res = await Get.find<PipedServices>()
              .removeFromPlaylist(playlist.playlistId, songIndex);
          if (res.code == 1) {
            plstCntroller.addNRemoveItemsinList(item, action: 'remove');
            return true;
          }
        }
        return false;
      }

      try {
        plstCntroller.addNRemoveItemsinList(item, action: 'remove');
        // ignore: empty_catches
      } catch (e) {}
    } catch (e) {
      printERROR("Some Error in removeSongFromPlaylist (might irrelavant): $e");
    }

    if (playlist.playlistId == "SongDownloads" ||
        playlist.playlistId == "SongsCache") {
      return true;
    }
    // Shared box (Hive hands every caller the same instance): never close
    // it here, or the player and other screens using it fail mid-write.
    return true;
  }
}

/// The song's album (browse id + name), when it has one.
({String id, String name})? _albumOf(MediaItem song) {
  final a = song.extras?['album'];
  if (a is Map && a['id'] is String && '${a['id']}'.isNotEmpty) {
    final name = '${a['name'] ?? song.album ?? ''}'.trim();
    return (id: a['id'] as String, name: name.isEmpty ? '${a['id']}' : name);
  }
  return null;
}
