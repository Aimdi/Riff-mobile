import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/riff_fast_scroller.dart';

import '/ui/theme/riff_tokens.dart';
import 'package:hive/hive.dart';

import '/services/podcast_playback_profile.dart';
import '/models/playlist.dart';
import 'package:share_plus/share_plus.dart';

import '/models/playling_from.dart';
import '/models/thumbnail.dart';
import '/services/playlist_covers.dart';
import '/services/podcast_service.dart';
import '/services/playlist_mix_service.dart';
import '/services/smart_shuffle.dart';
import '/services/taste_exclusions.dart';
import '/services/recently_played_days.dart';
import '../Podcasts/podcast_queue_screen.dart';
import '../Podcasts/podcasts_screen.dart';
import '../Podcasts/podcast_show_view.dart';
import '/services/discovery/discovery_types.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/playlist_album_scroll_behaviour.dart';
import '../../navigator.dart';
import '../../player/player_controller.dart';
import '../../widgets/add_to_playlist.dart' show showAddToPlaylistSheet;
import '../../widgets/confirm_dialog.dart';
import '../../widgets/create_playlist_dialog.dart';
import '../../widgets/generated_cover.dart';
import '../../widgets/collection_header.dart';
import '../../widgets/header_hero_fade.dart';
import '../Home/home_layout.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/riff_motion.dart';
import '../../widgets/shimmer_widgets/skeleton_fade.dart';
import '../../widgets/shimmer_widgets/song_list_shimmer.dart';
import '../../widgets/mix_transition_chip.dart';
import '../../widgets/playlist_export_dialog.dart';
import '../../widgets/podcast_follow_button.dart';
import '../../widgets/podcast_play.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/sort_widget.dart';
import '../Library/library_controller.dart';
import 'playlist_photo.dart';
import 'playlist_recommendations.dart';
import 'add_songs_sheet.dart';
import 'playlist_screen_controller.dart';
import '/ui/player/play_queue_order.dart' show playQueueFrom;
import '/ui/widgets/total_length.dart';

/// YouTube channel id (`UC…`) — compiled once, not per list row.
final _channelIdRe = RegExp(r'^UC[\w-]{20,}$');

/// Each playlist page's rows fading in as they replace its skeleton.
final _rowsFade = Expando<LoadedRowsFade>();

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
    // The cover behind the header: screen-wide, capped in height on wide
    // screens (it ran under the whole track list on a tablet).
    final backdrop = size.width < RiffComponentSizes.collectionBackdropMax
        ? size.width
        : RiffComponentSizes.collectionBackdropMax;
    final rowsFade = _rowsFade[playlistController] ??= LoadedRowsFade();
    // Podcasts and YouTube channels get the podcast show page; the Obx
    // always reads `playlist`, which an id-only open fills in later.
    return Obx(() {
      if (_isPodcastPage(playlistController.playlist.value)) {
        return _PodcastShow(c: playlistController, player: playerController);
      }
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
                        // Fades in as the page loads (a cover already in
                        // memory would otherwise cut in).
                        child: RiffFadeIn(
                            rise: 0,
                            child: Obx(() {
                              // A new photo shows straight away.
                              PlaylistCovers.rev.value;
                              final opacityValue = 1 -
                                  playlistController.scrollOffset.value /
                                      (size.width - 100);
                              return HeaderHeroFade(
                                opacity: opacityValue < 0 ||
                                        playlistController
                                                .isSearchingOn.isTrue &&
                                            !landscape
                                    ? 0
                                    : opacityValue,
                                color: Theme.of(context).canvasColor,
                                leftShadowOffset: -size.height,
                                bottomShadowOffset:
                                    landscape ? size.height : backdrop + 80,
                                // A photo of its own, else, with no art (or
                                // when it fails to load), the generated cover
                                // without the title (the header under it
                                // shows that).
                                child: !playlistController
                                            .playlist.value.hasArt ||
                                        _ownPhoto(
                                            playlistController.playlist.value)
                                    ? _heroCover(
                                        playlistController.playlist.value,
                                        landscape ? size.height : size.width,
                                        landscape ? null : backdrop)
                                    : RiffNetworkImage(
                                        imageUrl: Thumbnail(playlistController
                                                .playlist.value.thumbnailUrl)
                                            .extraHigh,
                                        fit: landscape
                                            ? BoxFit.fitHeight
                                            : BoxFit.cover,
                                        width: landscape ? null : size.width,
                                        height:
                                            landscape ? size.height : backdrop,
                                        memCacheWidth: landscape
                                            ? null
                                            : (size.width *
                                                    MediaQuery
                                                        .devicePixelRatioOf(
                                                            context))
                                                .round(),
                                        memCacheHeight: landscape
                                            ? (size.height *
                                                    MediaQuery
                                                        .devicePixelRatioOf(
                                                            context))
                                                .round()
                                            : null,
                                        // The original URL tried next fades its
                                        // own image or fallback in.
                                        errorFadesIn: false,
                                        errorWidget: (_, __, ___) =>
                                            RiffNetworkImage(
                                          imageUrl: playlistController
                                              .playlist.value.thumbnailUrl,
                                          fit: landscape
                                              ? BoxFit.fitHeight
                                              : BoxFit.cover,
                                          width: landscape ? null : size.width,
                                          height: landscape
                                              ? size.height
                                              : backdrop,
                                          memCacheWidth: landscape
                                              ? null
                                              : (size.width *
                                                      MediaQuery
                                                          .devicePixelRatioOf(
                                                              context))
                                                  .round(),
                                          memCacheHeight: landscape
                                              ? (size.height *
                                                      MediaQuery
                                                          .devicePixelRatioOf(
                                                              context))
                                                  .round()
                                              : null,
                                          errorWidget: (_, __, ___) =>
                                              _heroCover(
                                                  playlistController
                                                      .playlist.value,
                                                  landscape
                                                      ? size.height
                                                      : size.width,
                                                  landscape ? null : backdrop),
                                        ),
                                      ),
                              );
                            })))
                    : SizedBox(
                        height: backdrop,
                        width: size.width,
                      ),
              ),
              Column(
                children: [
                  Obx(() => CollectionTopBar(
                        title: playlistController.playlist.value.title,
                        showTitle: playlistController.appBarTitleVisible.isTrue,
                      )),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 800,
                        ),
                        child: RiffFastScroller(
                          // A long list gets the fast-scroll thumb (no letters: it's in
                          // the collection's own order).
                          itemExtent: RiffComponentSizes.songRowExtent,
                          builder: (context, scroll) => Obx(
                            () => ScrollConfiguration(
                              behavior: PlaylistAlbumScrollBehaviour(),
                              child: ListView.builder(
                                controller: scroll,
                                addRepaintBoundaries: true,
                                padding: EdgeInsets.only(
                                  top: playlistController.isSearchingOn.isTrue
                                      ? 0
                                      : landscape
                                          ? 110
                                          : 160,
                                  bottom: 200,
                                ),
                                // isContentFetched first: behind an empty
                                // list, || never read it, so the Obx missed
                                // a failed load and kept the shimmer.
                                itemCount: playlistController
                                            .isContentFetched.isFalse ||
                                        playlistController.songList.isEmpty
                                    ? 4
                                    : playlistController.songList.length +
                                        3 +
                                        (_showsRecommendations(
                                                playlistController)
                                            ? 1
                                            : 0),
                                // The recommendations move down a row with
                                // each song added: keep them (and what they
                                // showed) instead of loading new ones.
                                findChildIndexCallback: (key) => key ==
                                        _recommendationsKey(playlistController)
                                    ? playlistController.songList.length + 3
                                    : null,
                                itemBuilder: (_, index) {
                                  if (index == 0) {
                                    final header = _header(context,
                                        playlistController, playerController);
                                    // A cover flying in (CoverHero) is there
                                    // from the start; only the text fades.
                                    if (playlistController.coverHeroTag !=
                                        null) {
                                      return header;
                                    }
                                    return FadeTransition(
                                      opacity:
                                          playlistController.scaleAnimation,
                                      child: header,
                                    );
                                  } else if (index == 1) {
                                    // Podcasts / YT channels: no music actions;
                                    // Subscribe sits in the header instead.
                                    if (_isPodcastPage(
                                        playlistController.playlist.value)) {
                                      return const SizedBox(height: 8);
                                    }
                                    // Rebuilt with the photo, so ⋮ offers
                                    // to set or change it, and with the
                                    // taste profile's exclusions.
                                    return Obx(() {
                                      PlaylistCovers.rev.value;
                                      TasteExclusions.rev.value;
                                      return _actions(context,
                                          playlistController, playerController);
                                    });
                                  } else if (index == 2) {
                                    return SizedBox(
                                        height: playlistController
                                                .isSearchingOn.isTrue
                                            ? 60
                                            : 44,
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(right: 4),
                                          child: Obx(
                                            () => SortWidget(
                                              tag: playlistController
                                                  .playlist.value.playlistId,
                                              screenController:
                                                  playlistController,
                                              isSearchFeatureRequired: true,
                                              isPlaylistRearrageFeatureRequired:
                                                  !playlistController
                                                          .playlist
                                                          .value
                                                          .isCloudPlaylist &&
                                                      playlistController
                                                              .playlist
                                                              .value
                                                              .playlistId !=
                                                          "LIBRP" &&
                                                      playlistController
                                                              .playlist
                                                              .value
                                                              .playlistId !=
                                                          "SongDownloads" &&
                                                      playlistController
                                                              .playlist
                                                              .value
                                                              .playlistId !=
                                                          "SongsCache",
                                              isSongDeletetioFeatureRequired:
                                                  !playlistController.playlist
                                                      .value.isCloudPlaylist,
                                              itemCountTitle:
                                                  "${playlistController.songList.length}",
                                              totalLength: totalLength(
                                                  playlistController.songList),
                                              itemIcon: Icons.music_note,
                                              requiredSortTypes: {
                                                ...buildSortTypeSet(
                                                    false, true),
                                                ...songOrderSortTypes,
                                              },
                                              onSort: playlistController.onSort,
                                              onSearch:
                                                  playlistController.onSearch,
                                              onSearchClose: playlistController
                                                  .onSearchClose,
                                              onSearchStart: playlistController
                                                  .onSearchStart,
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
                                    if (playlistController
                                        .isContentFetched.isFalse) {
                                      rowsFade.skeleton();
                                    }
                                    return SizedBox(
                                      height: 300,
                                      child: playlistController
                                              .isContentFetched.isFalse
                                          ? const SongListShimmer(
                                              itemCount: 6, topPadding: 8)
                                          : RiffFadeIn(
                                              child: Center(
                                                child: Text(
                                                  "emptyPlaylist".tr,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall,
                                                ),
                                              ),
                                            ),
                                    );
                                  }

                                  final pl = playlistController.playlist.value;
                                  if (index ==
                                      playlistController.songList.length + 3) {
                                    return PlaylistRecommendations(
                                      key: _recommendationsKey(
                                          playlistController),
                                      songs:
                                          playlistController.songList.toList(),
                                      playlistTitle: pl.title,
                                      onAdd: playlistController.appendSong,
                                    );
                                  }
                                  final isPodcastList = pl.kind == 'podcast' ||
                                      pl.kind == 'yt_channel' ||
                                      pl.playlistId.startsWith('MPSP') ||
                                      _channelIdRe.hasMatch(pl.playlistId);
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
                                    return rowsFade.row(_PodcastEpisodeTile(
                                        song: song, onTap: playThis));
                                  }
                                  return rowsFade.row(Obx(() {
                                    final mixOn =
                                        playlistController.isMixMode.isTrue;
                                    // Only subscribe to analyses in mix mode
                                    // (isMixMode is always read, so the Obx
                                    // stays valid).
                                    final analysis = mixOn
                                        ? playlistController
                                            .mixAnalyses[song.id]
                                        : null;
                                    final isLast = songIndex >=
                                        playlistController.songList.length - 1;
                                    final gapStyle = mixOn && !isLast
                                        ? playlistController
                                            .transitionForGap(songIndex)
                                        : null;
                                    // Recently played by day, as Spotify's
                                    // and YouTube Music's histories.
                                    final day = pl.playlistId == 'LIBRP'
                                        ? _recentlyPlayedDay(
                                            playlistController, songIndex)
                                        : null;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          left: 4, right: 4),
                                      child: Column(
                                        children: [
                                          if (day != null)
                                            HomeSectionHeader(day,
                                                top: songIndex == 0
                                                    ? RiffSpacing.sm
                                                    : HomeLayout.sectionTop),
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
                                  }));
                                },
                              ),
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
                        _channelIdRe.hasMatch(pl.playlistId);
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
    });
  }
}

/// YouTube Music / YouTube podcast or channel, shown as a podcast page.
class _PodcastShow extends StatelessWidget {
  const _PodcastShow({required this.c, required this.player});
  final PlaylistScreenController c;
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final pl = c.playlist.value;
      final episodes = c.songList.toList();
      return PodcastShowView(
        playbackKey: podcastShowKeyForYoutube(pl.playlistId),
        title: pl.title,
        author: (pl.description ?? '').trim(),
        artUrl: pl.thumbnailUrl,
        description: '',
        episodes: episodes,
        loading: c.isContentFetched.isFalse,
        subscribed: c.isAddedToLibrary.isTrue,
        onToggleSubscribe: () {
          final add = c.isAddedToLibrary.isFalse;
          c.addNremoveFromLibrary(c.playlist.value, add: add).then((ok) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(snackbar(
              context,
              !ok
                  ? 'operationFailed'.tr
                  : add
                      ? 'subscribedAsPodcast'.tr
                      : 'removeFromLib'.tr,
              size: SanckBarSize.MEDIUM,
            ));
          });
        },
        onPlay: (i) async {
          if (Get.isRegistered<PlaylistMixService>()) {
            Get.find<PlaylistMixService>().deactivatePlayback();
          }
          // Episodes remember their show so its playback settings apply.
          final ok = await player.playPlayListSong(
            [for (final m in c.songList) withPodcastShowId(m, pl.playlistId)],
            i,
            playfrom: PlaylingFrom(
                name: pl.title,
                type: PlaylingFromType.PLAYLIST,
                id: pl.playlistId,
                item: pl),
            source: DiscoverySource.podcast,
          );
          if (!ok) snackOperationFailed();
        },
        onEpisodeLongPress: (m) => showAddToQueueSheet(context, m),
        onBack: () => Navigator.of(context).pop(),
        footer: c.showSimilarPodcasts.value
            ? _PodcastSimilarFooter(title: pl.title)
            : null,
      );
    });
  }
}

bool _ownPhoto(Playlist pl) => PlaylistCovers.pathFor(pl.playlistId) != null;

/// Recently played's day heading over its [index]th song, where a day
/// begins (and the list is in the order played).
String? _recentlyPlayedDay(PlaylistScreenController c, int index) {
  if (!Hive.isBoxOpen('LIBRP')) return null;
  final times = recentlyPlayedTimes(Hive.box('LIBRP').values);
  final days = recentlyPlayedHeadings(
      [for (final song in c.songList) times[song.id]], DateTime.now());
  return index < days.length ? days[index] : null;
}

Key _recommendationsKey(PlaylistScreenController c) =>
    ValueKey('recommendations:${c.playlist.value.playlistId}');

/// Songs to add show under your own playlists, unless you're searching or
/// arranging or picking songs in it.
bool _showsRecommendations(PlaylistScreenController c) {
  final pl = c.playlist.value;
  return !pl.isCloudPlaylist &&
      c.isDefaultPlaylist.isFalse &&
      !_isPodcastPage(pl) &&
      c.isSearchingOn.isFalse &&
      c.additionalOperationMode.value == OperationMode.none;
}

/// Header backdrop for a playlist without a cover of its own: the photo it
/// was given, else (or when that file is gone) its generated cover.
/// The art behind the header, [width] wide and [height] tall (square
/// unless given; cropped to fill).
Widget _heroCover(Playlist pl, double width, [double? height]) {
  final h = height ?? width;
  final generated = ClipRect(
    child: SizedBox(
      width: width,
      height: h,
      child: FittedBox(
        fit: BoxFit.cover,
        child: GeneratedCover.playlist(pl, size: width, showTitle: false),
      ),
    ),
  );
  final photo = PlaylistCovers.pathFor(pl.playlistId);
  if (photo == null) return generated;
  return Image.file(
    File(photo),
    width: width,
    height: h,
    fit: BoxFit.cover,
    frameBuilder: riffFadeInFrame,
    errorBuilder: (_, __, ___) => generated,
  );
}

bool _isPodcastPage(Playlist pl) =>
    pl.kind == 'podcast' ||
    pl.kind == 'yt_channel' ||
    pl.playlistId.startsWith('MPSP') ||
    _channelIdRe.hasMatch(pl.playlistId);

Widget _header(
    BuildContext context, PlaylistScreenController c, PlayerController player) {
  final pl = c.playlist.value;
  final isPodcast = _isPodcastPage(pl);
  // A library playlist's default ("Library Playlist") reads "Playlist".
  final description =
      isPodcast ? (pl.description ?? '').trim() : pl.ownDescription;
  final hero = c.coverHeroTag;
  return CollectionHeader(
    cover: ImageWidget(size: 96, playlist: pl),
    coverHeroTag: hero,
    textOpacity: hero == null ? null : c.scaleAnimation,
    title: pl.title,
    subtitle: isPodcast
        ? (description.isEmpty ? 'podcasts'.tr : description)
        : (description.isEmpty ? 'playlist'.tr : description),
    meta: isPodcast ? '' : collectionMetaLine(c.songList.toList()),
    onCoverTap: () {
      if (c.songList.isEmpty) return;
      _playPlaylistFrom(player, c, 0);
    },
    extra: !isPodcast
        ? null
        : Obx(() => PodcastFollowButton(
              following: c.isAddedToLibrary.isTrue,
              onPressed: () {
                final add = c.isAddedToLibrary.isFalse;
                c.addNremoveFromLibrary(c.playlist.value, add: add).then((ok) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                    context,
                    !ok
                        ? 'operationFailed'.tr
                        : add
                            ? 'subscribedAsPodcast'.tr
                            : 'removeFromLib'.tr,
                    size: SanckBarSize.MEDIUM,
                  ));
                });
              },
            )),
  );
}

Widget _actions(
    BuildContext context, PlaylistScreenController c, PlayerController player) {
  void snack(String key) {
    final ctx = context.mounted ? context : Get.context;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx)
        .showSnackBar(snackbar(ctx, key.tr, size: SanckBarSize.MEDIUM));
  }

  final pl = c.playlist.value;
  final songs = c.songList.toList();
  final isLocal = !pl.isCloudPlaylist && c.isDefaultPlaylist.isFalse;
  return CollectionActionRow(
    onPlay: songs.isEmpty ? null : () => _playPlaylistFrom(player, c, 0),
    onShuffle: songs.isEmpty
        ? null
        : () async {
            final list = playQueueFrom(c.songList, shuffle: true);
            if (Get.isRegistered<PlaylistMixService>()) {
              Get.find<PlaylistMixService>().deactivatePlayback();
            }
            final ok = await player.playPlayListSong(list, 0,
                playfrom: PlaylingFrom(
                    name: pl.title,
                    type: PlaylingFromType.PLAYLIST,
                    id: pl.playlistId,
                    item: pl));
            if (!ok) snackOperationFailed();
          },
    leading: [
      if (pl.isCloudPlaylist && !pl.isPipedPlaylist)
        Obx(() => CollectionSaveButton(
              saved: c.isAddedToLibrary.isTrue,
              onPressed: () {
                final add = c.isAddedToLibrary.isFalse;
                c
                    .addNremoveFromLibrary(c.playlist.value, add: add)
                    .then((ok) => snack(ok
                        ? add
                            ? "playlistBookmarkAddAlert"
                            : "listBookmarkRemoveAlert"
                        : "operationFailed"));
              },
            )),
      Obx(() => CollectionDownloadButton(
            id: c.playlist.value.playlistId,
            songs: () => c.songList.toList(),
            isDownloaded: c.isDownloaded.isTrue,
            tooltip: "downloadPlaylist".tr,
          )),
      // Mix mode: a stateful toggle, so it stays visible (accent when on).
      Obx(() {
        final on = c.isMixMode.isTrue;
        final analyzing = on && c.isAnalyzingMix.isTrue;
        return IconButton(
          tooltip: 'mix'.tr,
          onPressed: c.toggleMixMode,
          icon: analyzing
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: c.mixAnalyzeProgress.value > 0
                        ? c.mixAnalyzeProgress.value
                        : null,
                  ),
                )
              : Icon(Icons.tune_rounded,
                  size: 24,
                  color: on
                      ? Theme.of(context).colorScheme.secondary
                      : homeMutedColor(context)),
        );
      }),
    ],
    menu: [
      CollectionMenuItem(Icons.playlist_play_rounded, "playNext".tr, () async {
        final ok = await player.playNextList(c.songList.toList());
        snack(ok ? "playnextMsg" : "operationFailed");
      }),
      CollectionMenuItem(Icons.queue_music_rounded, "enqueueSongs".tr,
          () async {
        final ok =
            await player.enqueueSongList(c.songList.toList(), byYou: true);
        snack(ok ? "songEnqueueAlert" : "operationFailed");
      }),
      // Spotify's Add to other playlist: all of this one's songs at once.
      CollectionMenuItem(Icons.playlist_add_rounded,
          (isLocal ? 'addToOtherPlaylist' : 'addToPlaylist').tr, () {
        final list = c.songList.toList();
        if (list.isEmpty) return snack('emptyPlaylist');
        showAddToPlaylistSheet(context, list);
      }),
      // Spotify's Smart shuffle: songs like these mixed in.
      CollectionMenuItem(Icons.shuffle_on_rounded, 'smartShuffle'.tr, () async {
        final list = c.songList.toList();
        if (list.isEmpty) return;
        final picks = await smartShufflePicks(list);
        if (Get.isRegistered<PlaylistMixService>()) {
          Get.find<PlaylistMixService>().deactivatePlayback();
        }
        final ok = await player.playPlayListSong(
            smartShuffleOrder(list, picks), 0,
            playfrom: PlaylingFrom(
                name: pl.title,
                type: PlaylingFromType.PLAYLIST,
                id: pl.playlistId,
                item: pl));
        snack(!ok
            ? "operationFailed"
            : picks.isEmpty
                ? 'smartShuffleNoPicks'
                : 'smartShuffleOn');
      }),
      CollectionMenuItem(Icons.sensors, "startRadio".tr, () async {
        final list = c.songList.toList();
        if (list.isEmpty) return snack("radioNotAvailable");
        final ok = await player.startRadio(list.first);
        if (!ok) snack("radioNotAvailable");
      }),
      if (c.isMixMode.isTrue)
        CollectionMenuItem(Icons.auto_awesome, 'mixSmartOrder'.tr, () async {
          final ok = await c.smartOrderForMix();
          snack(ok ? 'mixSmartOrderDone' : 'operationFailed');
        }),
      if (c.isAddedToLibrary.isTrue)
        CollectionMenuItem(Icons.cloud_sync_outlined, "syncPlaylistSongs".tr,
            () async {
          final ok = await c.syncPlaylistSongs();
          snack(ok ? "pipedplstSyncAlert" : "errorOccuredAlert");
        }),
      if (pl.isCloudPlaylist)
        CollectionMenuItem(Icons.share_outlined, "sharePlaylist".tr, () {
          if (pl.isPipedPlaylist) {
            Share.share("https://piped.video/playlist?list=${pl.playlistId}");
            return;
          }
          final id = pl.playlistId.startsWith("VL")
              ? pl.playlistId.substring(2)
              : pl.playlistId;
          Share.share("https://youtube.com/playlist?list=$id");
        })
      // One of your own, as Spotify shares yours: a link and its M3U file.
      else if (pl.playlistId != 'LIBRP' && c.songList.isNotEmpty)
        CollectionMenuItem(Icons.share_outlined, "sharePlaylist".tr, () async {
          try {
            await c.sharePlaylist();
          } catch (e) {
            snack('operationFailed');
          }
        }),
      // YouTube Music's Clear history, with Undo as the podcast history's.
      if (pl.playlistId == 'LIBRP')
        CollectionMenuItem(Icons.delete_sweep_outlined, "clearHistory".tr,
            () async {
          final target = undoSnackbarTarget(context);
          final held = await clearRecentlyPlayed();
          c.songList.clear();
          showUndoSnackbar(target, 'historyCleared'.tr, onUndo: () async {
            await restoreRecentlyPlayed(held);
            c.fetchSongsfromDatabase('LIBRP');
          });
        }),
      // Spotify's "Exclude from your Taste Profile": what plays from it
      // isn't counted in stats or recommendations.
      if (pl.playlistId != 'LIBRP')
        TasteExclusions.excludes(pl.playlistId)
            ? CollectionMenuItem(Icons.insights_rounded, 'includeInTaste'.tr,
                () async {
                await TasteExclusions.setExcluded(pl.playlistId, false);
                snack('includedInTasteMsg');
              })
            : CollectionMenuItem(
                Icons.not_interested_rounded, 'excludeFromTaste'.tr, () async {
                await TasteExclusions.setExcluded(pl.playlistId, true);
                snack('excludedFromTasteMsg');
              }),
      CollectionMenuItem(Icons.file_upload_outlined, "exportPlaylist".tr, () {
        showDialog(
          context: context,
          builder: (dialogContext) =>
              PlaylistExportDialog(controller: c, parentContext: context),
        );
      }),
      if (pl.isPipedPlaylist)
        CollectionMenuItem(Icons.block, "blacklistPipedPlaylist".tr, () async {
          Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop();
          final ok = await Get.find<LibraryPlaylistsController>()
              .blacklistPipedPlaylist(c.playlist.value);
          snack(ok ? "playlistBlacklistAlert" : "operationFailed");
        }),
      if (isLocal) ...[
        // Spotify's "Add to this playlist": search and add, staying here.
        CollectionMenuItem(Icons.add_rounded, "addSongs".tr,
            () => showAddSongsSheet(context, c)),
        CollectionMenuItem(Icons.edit_outlined, "editPlaylistDetails".tr, () {
          showDialog(
            context: context,
            builder: (context) => CreateNRenamePlaylistPopup(
                renamePlaylist: true, playlist: c.playlist.value),
          );
        }),
        CollectionMenuItem(
            Icons.add_photo_alternate_outlined,
            (_ownPhoto(pl) ? "changePlaylistPhoto" : "setPlaylistPhoto").tr,
            () => pickPlaylistPhoto(context, pl.playlistId)),
        if (_ownPhoto(pl))
          CollectionMenuItem(
              Icons.hide_image_outlined,
              "removePlaylistPhoto".tr,
              () => PlaylistCovers.remove(pl.playlistId)),
        CollectionMenuItem(Icons.delete_outline_rounded, "removePlaylist".tr,
            () async {
          // Deleting erases the playlist's songs from disk: ask first.
          final confirmed = await confirmDestructive(
            context,
            title: "deletePlaylistTitle".tr,
            message: "deletePlaylistMessage"
                .trParams({'name': c.playlist.value.title}),
            confirmLabel: "delete".tr,
          );
          if (!confirmed) return;
          c.addNremoveFromLibrary(c.playlist.value, add: false).then((ok) {
            Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop();
            snack(ok ? "playlistRemovedAlert" : "operationFailed");
          });
        }),
      ],
    ],
  );
}

Future<void> _playPlaylistFrom(
  PlayerController playerController,
  PlaylistScreenController playlistController,
  int index,
) async {
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
  final ok = await playerController.playPlayListSong(
    List<MediaItem>.from(playlistController.songList),
    index,
    playfrom: PlaylingFrom(
      name: pl.title,
      type: PlaylingFromType.PLAYLIST,
      id: pl.playlistId,
      item: pl,
    ),
  );
  if (!ok) snackOperationFailed();
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
            padding: const EdgeInsets.only(
                left: RiffSpacing.xl,
                top: RiffSpacing.md,
                right: RiffSpacing.md,
                bottom: RiffSpacing.md),
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
                        child: RiffNetworkImage(
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
                                  .labelMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.color),
                            ),
                            if (durationText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  durationText,
                                  style: Theme.of(context).textTheme.bodyMedium,
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
    final playerMin = Get.find<PlayerController>().playerPanelMinHeight.value;
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
            padding: const EdgeInsets.only(
                left: RiffSpacing.lg,
                right: RiffSpacing.lg,
                bottom: RiffSpacing.sm),
            child: Text(
              "similarPodcasts".tr,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.textTheme.titleSmall?.color),
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
                : RiffFadeIn(
                    child: ListView.separated(
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
                                child: RiffNetworkImage(
                                  imageUrl: art,
                                  width: tile,
                                  height: tile,
                                  memCacheWidth: (tile *
                                          MediaQuery.devicePixelRatioOf(
                                              context))
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
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.labelSmall?.color),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )),
          ),
        ],
      ),
    );
  }
}
