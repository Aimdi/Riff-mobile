import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/wizestream_service.dart';

import '../../models/media_Item_builder.dart';
import '../../models/media_item_extras.dart';
import '../../services/ban_service.dart';
import '../../services/discovery/discovery_service.dart';
import '../../services/discovery/discovery_tag.dart';
import '../../utils/hive_boxes.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '/utils/helper.dart';
import '/services/piped_service.dart';
import '/ui/widgets/sleep_timer_bottom_sheet.dart';
import '/ui/player/components/player_control.dart' show sleepTimerBadge;
import '/ui/player/components/lyrics_share.dart';
import '/ui/player/components/lyrics_timing_sheet.dart';
import '/ui/player/components/lyrics_search_sheet.dart';
import '/services/lyrics_timing.dart';
import '/services/lyrics_translation.dart';
import 'cust_switch.dart';
import '/ui/player/player_controller.dart';
import '../screens/Library/library_controller.dart';
import '/ui/widgets/add_to_playlist.dart';
import '/ui/widgets/favorite_heart_button.dart';
import '/ui/widgets/not_interested_action.dart';
import '/ui/widgets/queue_undo.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/utils/sheet_insets.dart';
import '/utils/content_filters.dart';
import '../../models/playlist.dart';
import '../../models/playling_from.dart';
import '../navigator.dart';
import 'discovery/similar_songs_sheet.dart';
import 'song_download_btn.dart';
import 'image_widget.dart';
import 'audio_output_tile.dart';
import 'riff_sheet.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'song_credits_dialog.dart';
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
      this.calledFromQueue = false,
      this.showPlayerTools = false,
      this.onLyrics});
  final MediaItem song;
  final Playlist? playlist;
  final bool calledFromPlayer;
  final bool calledFromQueue;

  /// The full player's ⋮: lyrics and the sleep timer sit right under the
  /// quick actions, since the player has no button row of its own.
  final bool showPlayerTools;

  /// How this player shows lyrics; null toggles them over the cover.
  final VoidCallback? onLyrics;

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
    final fg = theme.colorScheme.onSurface;
    final hasAlbum =
        ((song.extras?['album'] as Map?)?['id'] ?? '').toString().isNotEmpty;
    final inEditablePlaylist = (playlist != null &&
            !playlist!.isCloudPlaylist &&
            !(playlist!.playlistId == "LIBRP")) ||
        (playlist != null && playlist!.isPipedPlaylist);

    void snack(String text, {SanckBarSize size = SanckBarSize.MEDIUM}) {
      final ctx = Get.context;
      if (ctx == null || !ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(snackbar(ctx, text, size: size));
    }

    return Padding(
      // Callers should use useRootNavigator: true so the sheet clears the
      // mini player; keep system safe-area inset here.
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context, liftAboveMiniPlayer: false) +
            RiffSpacing.sm,
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
                padding: const EdgeInsets.only(
                    left: RiffSpacing.lg,
                    top: RiffSpacing.sm,
                    right: RiffSpacing.md,
                    bottom: RiffSpacing.md),
                child: Row(
                  children: [
                    ImageWidget(
                        song: song, size: RiffComponentSizes.sheetHeaderArt),
                    const SizedBox(width: RiffSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: fg)),
                          const SizedBox(height: RiffSpacing.xxs),
                          Text(song.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
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
                    HapticFeedback.lightImpact();
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
            const SizedBox(height: RiffSpacing.xs),
            if (showPlayerTools) PlayerToolTiles(onLyrics: onLyrics),
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
                  HapticFeedback.lightImpact();
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
            // Spotify's View credits (YouTube Music's View song credits).
            RiffSheetTile(
              icon: Icons.groups_outlined,
              title: "credits".tr,
              onTap: () => showDialog(
                context: context,
                builder: (context) => SongCreditsDialog(song: song),
              ),
            ),
            const RiffSheetDivider(),
            if (inEditablePlaylist)
              RiffSheetTile(
                icon: Icons.remove_circle_outline_rounded,
                title: playlist!.title == "Library Songs"
                    ? "removeFromLib".tr
                    : "removeFromPlaylist".tr,
                onTap: () {
                  Navigator.of(context).pop();
                  removeFromPlaylistWithUndo(song, playlist!);
                },
              ),
            // The player's and Up Next's: the playlist playing, when it's
            // one of yours with this song (Spotify's Remove from this
            // playlist).
            if (playlist == null && (calledFromPlayer || calledFromQueue))
              Obx(() {
                final playing = songInfoController.playingPlaylist.value;
                if (playing == null) return const SizedBox.shrink();
                return RiffSheetTile(
                  icon: Icons.remove_circle_outline_rounded,
                  title: "removeFromPlaylist".tr,
                  subtitle: playing.title,
                  onTap: () {
                    Navigator.of(context).pop();
                    removeFromPlaylistWithUndo(song, playing);
                  },
                );
              }),
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
                    removeFromQueueWithUndo(song);
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
                            snack("operationFailed".tr, size: SanckBarSize.BIG);
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
            if (!showPlayerTools)
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
              padding: const EdgeInsets.only(
                  left: RiffSpacing.lg,
                  top: RiffSpacing.md,
                  right: RiffSpacing.lg,
                  bottom: RiffSpacing.sm),
              child: Text("openIn".tr,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.lg,
                  right: RiffSpacing.lg,
                  bottom: RiffSpacing.sm),
              child: Wrap(
                spacing: RiffSpacing.sm,
                runSpacing: RiffSpacing.sm,
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
            // YouTube Music's and Spotify's "Not interested", for a song
            // picked for you (radio, Autoplay, a mix, Smart shuffle).
            if ((calledFromPlayer || calledFromQueue) &&
                sourceFromMediaItem(song).isPickedForYou)
              RiffSheetTile(
                icon: Icons.thumb_down_off_alt_rounded,
                title: "notInterested".tr,
                onTap: () {
                  Navigator.of(context).pop();
                  markNotInterested(song);
                },
              ),
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

/// Lyrics, the sleep timer (with the time left while it runs) and the
/// output switcher, for the full player's ⋮ sheet. All but the translation
/// switch close the sheet.
class PlayerToolTiles extends StatelessWidget {
  const PlayerToolTiles({super.key, this.onLyrics});

  /// How the player shows lyrics (the gesture player opens a dialog);
  /// null toggles them over the cover.
  final VoidCallback? onLyrics;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(() {
      final lyricsOn = playerController.showLyricsflag.isTrue;
      final sleepOn = playerController.isSleepTimerActive.isTrue;
      final left = sleepTimerBadge(playerController.timerDurationLeft.value);
      // Only synced lyrics have a timing to move.
      final lyrics = playerController.lyrics;
      final synced = '${lyrics['synced'] ?? ''}'.isNotEmpty ||
          '${lyrics['ttml'] ?? ''}'.isNotEmpty;
      final delay =
          LyricsTiming.delayMs(playerController.currentSong.value?.id);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffSheetTile(
            icon: lyricsOn ? Icons.lyrics : Icons.lyrics_outlined,
            title: (lyricsOn ? "hideLyrics" : "showLyrics").tr,
            onTap: () {
              Navigator.of(context).pop();
              if (!lyricsOn) HapticFeedback.lightImpact();
              final show = onLyrics;
              show != null ? show() : playerController.showLyrics();
            },
          ),
          RiffSheetTile(
            icon: Icons.format_quote_rounded,
            title: "shareLyrics".tr,
            onTap: () {
              Navigator.of(context).pop();
              showLyricsShareSheet(
                  playerController.homeScaffoldkey.currentContext ??
                      Get.context);
            },
          ),
          RiffSheetTile(
            icon: Icons.translate_rounded,
            title: "translateLyrics".tr,
            onTap: () =>
                LyricsTranslation.setEnabled(LyricsTranslation.enabled.isFalse),
            trailing: CustSwitch(
              value: LyricsTranslation.enabled.isTrue,
              onChanged: LyricsTranslation.setEnabled,
            ),
          ),
          if (synced)
            RiffSheetTile(
              icon: Icons.av_timer_rounded,
              title: "lyricsTiming".tr,
              subtitle: delay == 0 ? null : lyricsTimingLabel(delay),
              onTap: () {
                Navigator.of(context).pop();
                showLyricsTimingSheet(
                    playerController.homeScaffoldkey.currentContext ??
                        Get.context);
              },
            ),
          // Wrong lyrics, or none: find them (Metrolist's lyrics search).
          RiffSheetTile(
            icon: Icons.manage_search_rounded,
            title: "searchLyrics".tr,
            onTap: () {
              Navigator.of(context).pop();
              showLyricsSearchSheet(
                  playerController.homeScaffoldkey.currentContext ??
                      Get.context);
            },
          ),
          RiffSheetTile(
            icon: sleepOn ? Icons.bedtime : Icons.bedtime_outlined,
            title: "sleepTimer".tr,
            subtitle: sleepOn && left.isNotEmpty ? '$left ${"left".tr}' : null,
            onTap: () {
              Navigator.of(context).pop();
              showSleepTimerSheet(
                  playerController.homeScaffoldkey.currentContext ??
                      Get.context);
            },
          ),
          const AudioOutputTile(),
        ],
      );
    });
  }
}

class SongInfoController extends GetxController
    with RemoveSongFromPlaylistMixin {
  final isCurrentSongFav = false.obs;
  final MediaItem song;
  final bool calledFromPlayer;
  List artistList = [].obs;
  final isDownloaded = false.obs;

  /// The playlist playing, when it's one of yours with this song in it
  /// ([yourPlaylistPlaying]): the player's and Up Next's ⋮ can take the
  /// song out of it.
  final playingPlaylist = Rxn<Playlist>();
  SongInfoController(this.song, this.calledFromPlayer) {
    _setInitStatus(song);
    _findPlayingPlaylist();
  }

  Future<void> _findPlayingPlaylist() async {
    if (!Get.isRegistered<PlayerController>()) return;
    final found = await yourPlaylistPlaying(
        Get.find<PlayerController>().playinfrom.value, song);
    if (!isClosed) playingPlaylist.value = found;
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
  /// [onRemovedAt] gets the song's position when it came out of a local
  /// playlist, so [restoreSongToPlaylist] can put it back (Undo).
  Future<bool> removeSongFromPlaylist(MediaItem item, Playlist playlist,
      {void Function(int index)? onRemovedAt}) async {
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
      if (index >= 0) {
        if (playlist.playlistId == HiveBoxes.libFav &&
            Get.isRegistered<PlayerController>()) {
          // Unliked: by song id, and on YouTube Music / Spotify too, or
          // like sync would bring it back.
          await Get.find<PlayerController>()
              .toggleFavouriteFor(item, adding: false);
        } else {
          await box.deleteAt(index);
        }
        onRemovedAt?.call(index);
      }
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

  /// Undo for [removeSongFromPlaylist] on a local playlist: puts [item]
  /// back at [index] (clamped), in storage and on the open screen.
  Future<void> restoreSongToPlaylist(
      MediaItem item, Playlist playlist, int index) async {
    final box = await Hive.openBox(playlist.playlistId);
    final values = box.values.toList();
    if (values.any((v) => v is Map && v['videoId'] == item.id)) return;
    final at = index.clamp(0, values.length);
    if (playlist.playlistId == HiveBoxes.libFav &&
        Get.isRegistered<PlayerController>()) {
      // Liked again, under its song id (and on YouTube Music / Spotify).
      await Get.find<PlayerController>().toggleFavouriteFor(item, adding: true);
      return;
    }
    values.insert(at, MediaItemBuilder.toJson(item));
    // Positions are the order: rewrite them 0..n-1 in one batch.
    await box.clear();
    await box.putAll({for (var i = 0; i < values.length; i++) i: values[i]});
    try {
      final screen = Get.find<PlaylistScreenController>(
          tag: Key(playlist.playlistId).hashCode.toString());
      final shown = screen.songList.length;
      screen.addNRemoveItemsinList(item,
          action: 'add', index: at.clamp(0, shown));
    } catch (_) {
      // The playlist isn't open; storage is enough.
    }
  }
}

/// Removes [song] from [playlist] and says so; for local playlists and
/// the library the snackbar has Undo, which puts the song back where it
/// was.
Future<void> removeFromPlaylistWithUndo(MediaItem song, Playlist playlist,
    {BuildContext? context}) async {
  // Before any await: a swiped row is gone once the list updates.
  final target = undoSnackbarTarget(context);
  if (playlist.playlistId == "SongDownloads" ||
      playlist.playlistId == "SongsCache") {
    return _removeFromLibraryWithUndo(song, playlist, target);
  }
  final remover = _PlaylistSongRemover();
  int? removedAt;
  final ok = await remover.removeSongFromPlaylist(song, playlist,
      onRemovedAt: (i) => removedAt = i);
  final at = removedAt;
  showUndoSnackbar(
    target,
    ok
        ? "removedFromPlaylist".trParams({'name': playlist.title})
        : "operationFailed".tr,
    onUndo: ok && at != null
        ? () => remover.restoreSongToPlaylist(song, playlist, at)
        : null,
  );
}

class _PlaylistSongRemover with RemoveSongFromPlaylistMixin {}

/// Whether you can take songs out of [playlist] from the player: it's one
/// you made or imported in Riff, not a Library list (Favorites has the
/// heart), a mix Riff makes, or one on YouTube Music or Piped.
bool isYourPlaylist(Playlist playlist) =>
    !playlist.isCloudPlaylist &&
    !playlist.isPipedPlaylist &&
    !playlist.playlistId.startsWith('RIFF_') &&
    !const {
      HiveBoxes.libRp,
      HiveBoxes.libFav,
      HiveBoxes.songsCache,
      HiveBoxes.songDownloads,
    }.contains(playlist.playlistId);

/// The playlist playing ([from]), as the Library has it now (renamed, or
/// gone), when it's one of yours with [song] in it: the player's and Up
/// Next's ⋮ offer to take the song out of it, as Spotify's Now Playing
/// does (Remove from this playlist).
Future<Playlist?> yourPlaylistPlaying(PlaylingFrom from, MediaItem song) async {
  if (from.type != PlaylingFromType.PLAYLIST || from.id.isEmpty) return null;
  try {
    final saved = (await HiveBoxes.open('LibraryPlaylists')).get(from.id);
    if (saved is! Map) return null;
    final playlist = Playlist.fromJson(saved);
    if (playlist.playlistId != from.id || !isYourPlaylist(playlist)) {
      return null;
    }
    final songs = await HiveBoxes.open(from.id);
    return songs.values.any((s) => s is Map && s['videoId'] == song.id)
        ? playlist
        : null;
  } catch (_) {
    // Storage that won't open: nothing to offer.
    return null;
  }
}

/// The library's version: the song leaves the Songs list (and an open
/// Downloads / Cached screen) at once, its download or cached copy is
/// deleted only when the snackbar goes without Undo.
Future<void> _removeFromLibraryWithUndo(
    MediaItem song, Playlist playlist, UndoSnackbarTarget? target) async {
  final library = Get.find<LibrarySongsController>();
  final tag = Key(playlist.playlistId).hashCode.toString();
  final screen = Get.isRegistered<PlaylistScreenController>(tag: tag)
      ? Get.find<PlaylistScreenController>(tag: tag)
      : null;
  final screenIndex = screen?.songList.indexWhere((s) => s.id == song.id) ?? -1;
  if (screenIndex >= 0) screen!.addNRemoveItemsinList(song, action: 'remove');
  final removal = await library.takeOutOfLibrary(song);
  if (removal == null) return;
  final shown = showUndoSnackbar(
    target,
    "removedFromLibrary".tr,
    onUndo: () async {
      await library.undoRemoval(removal);
      if (screen != null &&
          !screen.isClosed &&
          screenIndex >= 0 &&
          screen.songList.every((s) => s.id != song.id)) {
        screen.addNRemoveItemsinList(song,
            action: 'add', index: screenIndex.clamp(0, screen.songList.length));
      }
    },
  );
  if (shown == null) {
    // Nowhere to offer Undo.
    await library.commitRemoval(removal);
    return;
  }
  // Closed any other way (timed out, swiped, replaced): no Undo now.
  shown.closed.then((reason) {
    if (reason != SnackBarClosedReason.action) library.commitRemoval(removal);
  });
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
