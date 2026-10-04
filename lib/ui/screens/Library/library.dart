import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/models/playling_from.dart';
import '/services/cloud_music_service.dart';
import '/services/discovery/discovery_tag.dart';
import '/services/discovery/discovery_types.dart';
import '/services/spotify_auth_service.dart';
import '/ui/screens/Plugins/spotify_pages.dart';
import '../../navigator.dart';
import '../../player/play_queue_order.dart';
import '../../player/player_controller.dart';
import '../../utils/riff_tokens.dart';
import '../../utils/theme_controller.dart';
import '../../widgets/modification_list.dart';
import '../../widgets/piped_sync_widget.dart';
import '../../widgets/content_list_widget_item.dart';
import '../../widgets/empty_play_hint.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/list_widget.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/shimmer_widgets/song_list_shimmer.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/sort_widget.dart';
import '../Cloud/cloud_play.dart';
import '../Cloud/cloud_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '../../theme/riff_spacing.dart';
import '../Home/home_layout.dart';
import 'library_controller.dart';
import '/ui/theme/riff_text_metrics.dart';

class SongsLibraryWidget extends StatelessWidget {
  const SongsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    final libSongsController = Get.find<LibrarySongsController>();
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(top: 10)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isBottomNavActive)
            Obx(() {
              final cloudMode = libSongsController.showCloudSongs.value;
              final canPlay = shouldShowLibrarySongsPlayBar(
                cloudMode: cloudMode,
                songCount: libSongsController.librarySongsList.length,
              );
              return LibraryHeader(
                title: cloudMode ? "cloud".tr : "libSongs".tr,
                actions: [
                  if (canPlay) ...[
                    IconButton(
                      tooltip: 'shuffle'.tr,
                      icon: const Icon(Icons.shuffle_rounded, size: 22),
                      onPressed: () => _playLibrarySongs(shuffle: true),
                    ),
                    LibraryPlayButton(
                        onPressed: () => _playLibrarySongs(shuffle: false)),
                  ],
                ],
              );
            }),
          if (!isBottomNavActive) const _LibraryPinnedRow(),
          Obx(() {
            final cloudMode = libSongsController.showCloudSongs.value;
            final cloud = Get.find<CloudMusicService>();
            final count = cloudMode
                ? (cloud.isConnected.value ? cloud.songs.length : 0)
                : libSongsController.librarySongsList.length;
            return SortWidget(
              tag: "LibSongSort",
              screenController: libSongsController,
              itemCountTitle: "$count",
              itemIcon: Icons.music_note,
              requiredSortTypes: buildSortTypeSet(true, true),
              isSearchFeatureRequired: !cloudMode,
              isSongDeletetioFeatureRequired: !cloudMode,
              isCloudFeatureRequired: true,
              isCloudModeActive: cloudMode,
              onCloudToggle: () => libSongsController.toggleCloudSongs(),
              onSort: (type, ascending) {
                if (!cloudMode) {
                  libSongsController.onSort(type, ascending);
                }
              },
              onSearch: libSongsController.onSearch,
              onSearchClose: libSongsController.onSearchClose,
              onSearchStart: libSongsController.onSearchStart,
              startAdditionalOperation:
                  libSongsController.startAdditionalOperation,
              selectAll: libSongsController.selectAll,
              performAdditionalOperation:
                  libSongsController.performAdditionalOperation,
              cancelAdditionalOperation:
                  libSongsController.cancelAdditionalOperation,
            );
          }),
          // Bottom-nav layout has no header: keep Play all / Shuffle.
          if (isBottomNavActive)
            Obx(() {
              if (!shouldShowLibrarySongsPlayBar(
                cloudMode: libSongsController.showCloudSongs.value,
                songCount: libSongsController.librarySongsList.length,
              )) {
                return const SizedBox.shrink();
              }
              return const _LibrarySongsPlayBar();
            }),
          Expanded(
            child: Obx(() {
              if (libSongsController.showCloudSongs.value) {
                return const _CloudSongsPane();
              }
              return GetX<LibrarySongsController>(builder: (controller) {
                return controller.librarySongsList.isNotEmpty
                    ? (controller.additionalOperationMode.value ==
                            OperationMode.none
                        // ListWidget returns an Expanded, so it needs a Flex
                        // parent (it sat directly in this Expanded before:
                        // "Incorrect use of ParentDataWidget").
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Column(
                              children: [
                                ListWidget(
                                  controller.librarySongsList,
                                  "library Songs",
                                  true,
                                  isPlaylistOrAlbum: true,
                                  playlist: Playlist(
                                      title: "Library Songs",
                                      playlistId: "SongDownloads",
                                      thumbnailUrl: "",
                                      isCloudPlaylist: false),
                                ),
                              ],
                            ),
                          )
                        : ModificationList(
                            mode: controller.additionalOperationMode.value,
                            screenController: controller,
                          ))
                    : EmptyPlayHint(message: "noOfflineSong".tr);
              });
            }),
          ),
        ],
      ),
    );
  }
}

/// Plays the offline library songs in order or shuffled.
Future<void> _playLibrarySongs({required bool shuffle}) async {
  if (!Get.isRegistered<LibrarySongsController>() ||
      !Get.isRegistered<PlayerController>()) {
    return;
  }
  final songs = Get.find<LibrarySongsController>().librarySongsList;
  if (songs.isEmpty) return;
  final queue = playQueueFrom(songs, shuffle: shuffle);
  final ok = await Get.find<PlayerController>().playPlayListSong(
    queue,
    0,
    playfrom: PlaylingFrom(
      type: PlaylingFromType.PLAYLIST,
      name: 'libSongs'.tr,
    ),
    source: DiscoverySource.downloads,
  );
  if (!ok) _snackPlayFailed();
}

/// Library tab title row: title on the left, tab actions on the right.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader(
      {super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          right: RiffSpacing.sm,
          bottom: RiffSpacing.xxs),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Round accent play button for a library header.
class LibraryPlayButton extends StatelessWidget {
  const LibraryPlayButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: accent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Tooltip(
            message: 'playAll'.tr,
            child: const SizedBox.square(
              dimension: 40,
              child: Icon(Icons.play_arrow_rounded,
                  size: 26, color: RiffSurfaces.voidBlack),
            ),
          ),
        ),
      ),
    );
  }
}

/// Library grid: 3 columns on phones (2 when narrow), more on tablets,
/// covers sized to fill each column.
({int columns, double cover}) libraryGridMetrics(double width) {
  final columns = width >= 1100
      ? 6
      : width >= 720
          ? 4
          : width >= 380
              ? 3
              : 2;
  final cover =
      (width - HomeLayout.gutter * 2 - HomeLayout.cardGap * (columns - 1)) /
          columns;
  return (columns: columns, cover: cover);
}

/// Play all / Shuffle for the offline Songs tab (bottom-nav layout).
class _LibrarySongsPlayBar extends StatelessWidget {
  const _LibrarySongsPlayBar();

  Future<void> _play({required bool shuffle}) =>
      _playLibrarySongs(shuffle: shuffle);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.textTheme.titleMedium?.color;
    final style = TextButton.styleFrom(
      foregroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.sm, right: RiffSpacing.md, bottom: RiffSpacing.xs),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _play(shuffle: false),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text('playAll'.tr),
            style: style,
          ),
          TextButton.icon(
            onPressed: () => _play(shuffle: true),
            icon: const Icon(Icons.shuffle, size: 18),
            label: Text('shuffle'.tr),
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Cloud songs (or connect form) shown when the Songs toolbar cloud toggle is on.
class _CloudSongsPane extends StatelessWidget {
  const _CloudSongsPane();

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    return Obx(() {
      if (cloud.isConnected.isFalse) {
        return const CloudLoginForm();
      }
      if (cloud.isLoading.value && cloud.songs.isEmpty) {
        return const SongListShimmer(itemCount: 8, topPadding: 12);
      }
      if (cloud.songs.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('cloudNoSongs'.tr,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => fetchAndPlayCloudRandomMix(cloud),
                icon: const Icon(Icons.casino_outlined),
                label: Text('cloudRandomMix'.tr),
              ),
            ],
          ),
        );
      }
      final list = cloud.songs.toList();
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 200, right: 8),
        itemCount: list.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('cloudRandomMix'.tr,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  if (shouldShowCloudSongsPlayBar(
                    connected: cloud.isConnected.isTrue,
                    songCount: list.length,
                  ))
                    IconButton(
                      tooltip: 'playAll'.tr,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      onPressed: () => playCloudSongsOrNotify(
                        cloud.toMediaItems(list),
                        shuffle: false,
                      ),
                    ),
                  IconButton(
                    tooltip: 'shuffle'.tr,
                    icon: const Icon(Icons.casino_outlined, size: 20),
                    onPressed: () => fetchAndPlayCloudRandomMix(cloud),
                  ),
                  TextButton(
                    onPressed: () => cloud.logout(),
                    child: Text('disconnect'.tr),
                  ),
                ],
              ),
            );
          }
          return CloudSongTile(songs: list, index: i - 1);
        },
      );
    });
  }
}

class PlaylistNAlbumLibraryWidget extends StatefulWidget {
  const PlaylistNAlbumLibraryWidget(
      {super.key, this.isAlbumContent = true, this.isBottomNavActive = false});
  final bool isAlbumContent;
  final bool isBottomNavActive;

  @override
  State<PlaylistNAlbumLibraryWidget> createState() =>
      _PlaylistNAlbumLibraryWidgetState();
}

class _PlaylistNAlbumLibraryWidgetState
    extends State<PlaylistNAlbumLibraryWidget> {
  // One controller for the grid's lifetime — it used to be created inside
  // build (Obx/LayoutBuilder), leaking a controller on every rebuild.
  final _gridScroll = ScrollController(keepScrollOffset: false);

  bool get isAlbumContent => widget.isAlbumContent;
  bool get isBottomNavActive => widget.isBottomNavActive;

  @override
  void dispose() {
    _gridScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libralbumCntrller = Get.find<LibraryAlbumsController>();
    final librplstCntrller = Get.find<LibraryPlaylistsController>();
    final settingscrnController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;

    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(top: 10)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          if (!isBottomNavActive)
            LibraryHeader(
              title: isAlbumContent ? "libAlbums".tr : "libPlaylists".tr,
              actions: [
                if (!isAlbumContent &&
                    settingscrnController.isLinkedWithPiped.isTrue)
                  PipedSyncWidget(
                    padding: EdgeInsets.only(right: size.width * .02),
                  ),
              ],
            ),
          Obx(
            () => isAlbumContent
                ? SortWidget(
                    tag: "LibAlbumSort",
                    screenController: libralbumCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${libralbumCntrller.libraryAlbums.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(true),
                    onSort: (type, ascending) {
                      libralbumCntrller.onSort(type, ascending);
                    },
                    onSearch: libralbumCntrller.onSearch,
                    onSearchClose: libralbumCntrller.onSearchClose,
                    onSearchStart: libralbumCntrller.onSearchStart,
                  )
                : SortWidget(
                    tag: "LibPlaylistSort",
                    screenController: librplstCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${librplstCntrller.libraryPlaylists.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(),
                    onSort: (type, ascending) {
                      librplstCntrller.onSort(type, ascending);
                    },
                    onSearch: librplstCntrller.onSearch,
                    onSearchClose: librplstCntrller.onSearchClose,
                    onSearchStart: librplstCntrller.onSearchStart,
                    isImportFeatureRequired: true,
                  ),
          ),
          Expanded(
            child: Obx(
              () => (isAlbumContent
                      ? libralbumCntrller.libraryAlbums.isNotEmpty
                      : librplstCntrller.libraryPlaylists.isNotEmpty)
                  ? LayoutBuilder(builder: (context, constraints) {
                      final grid = libraryGridMetrics(constraints.maxWidth);
                      return GridView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(
                              left: HomeLayout.gutter,
                              top: RiffSpacing.sm,
                              right: HomeLayout.gutter,
                              bottom: RiffSpacing.listEnd),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: grid.columns,
                            crossAxisSpacing: HomeLayout.cardGap,
                            mainAxisSpacing: 14,
                            mainAxisExtent:
                                ContentListItem.heightFor(context, grid.cover),
                          ),
                          controller: _gridScroll,
                          itemCount: isAlbumContent
                              ? libralbumCntrller.libraryAlbums.length
                              : librplstCntrller.libraryPlaylists.length,
                          itemBuilder: (BuildContext context, int index) {
                            return ContentListItem(
                              content: isAlbumContent
                                  ? libralbumCntrller.libraryAlbums[index]
                                  : librplstCntrller.libraryPlaylists[index],
                              isLibraryItem: true,
                              size: grid.cover,
                            );
                          });
                    })
                  : EmptyPlayHint(
                      message: isAlbumContent
                          ? "noLibAlbums".tr
                          : "noLibPlaylist".tr),
            ),
          )
        ],
      ),
    );
  }
}

class LibraryArtistWidget extends StatelessWidget {
  const LibraryArtistWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final cntrller = Get.find<LibraryArtistsController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(top: 10)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          if (!isBottomNavActive) LibraryHeader(title: "libArtists".tr),
          Obx(
            () => SortWidget(
              tag: "LibArtistSort",
              screenController: cntrller,
              isAdditionalOperationRequired: false,
              isSearchFeatureRequired: true,
              itemCountTitle: "${cntrller.libraryArtists.length} ${"items".tr}",
              onSort: (type, ascending) {
                cntrller.onSort(type, ascending);
              },
              onSearch: cntrller.onSearch,
              onSearchClose: cntrller.onSearchClose,
              onSearchStart: cntrller.onSearchStart,
            ),
          ),
          Expanded(
            child: Obx(() => cntrller.libraryArtists.isEmpty
                ? EmptyPlayHint(message: "noLibArtists".tr)
                : LayoutBuilder(builder: (context, constraints) {
                    final grid = libraryGridMetrics(constraints.maxWidth);
                    return GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(
                          left: HomeLayout.gutter,
                          top: RiffSpacing.sm,
                          right: HomeLayout.gutter,
                          bottom: RiffSpacing.listEnd),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: grid.columns,
                        crossAxisSpacing: HomeLayout.cardGap,
                        mainAxisSpacing: 16,
                        mainAxisExtent: grid.cover +
                            10 +
                            riffLineHeight(
                                context, homeCardTitleStyle(context)) +
                            riffLineHeight(
                                context, homeCardSubtitleStyle(context)) +
                            6,
                      ),
                      itemCount: cntrller.libraryArtists.length,
                      itemBuilder: (context, index) => _LibraryArtistCard(
                        artist: cntrller.libraryArtists[index],
                        size: grid.cover,
                      ),
                    );
                  })),
          ),
        ],
      ),
    );
  }
}

/// Round artist card: photo, name and "Artist". Tap opens the artist;
/// long-press offers play, shuffle, radio and open.
class _LibraryArtistCard extends StatelessWidget {
  const _LibraryArtistCard({required this.artist, required this.size});
  final dynamic artist;
  final double size;

  void _open() => Get.toNamed(ScreenNavigationSetup.artistScreen,
      id: ScreenNavigationSetup.id, arguments: [false, artist]);

  Future<void> _play({bool shuffle = false, bool radio = false}) async {
    final ok = await playArtist(artist, shuffle: shuffle, radio: radio);
    if (!ok) _open();
  }

  void _actions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: riffSheetShape,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('${artist.name}', subtitle: 'artist'.tr),
            RiffQuickActions([
              RiffQuickAction(
                  icon: Icons.play_arrow_rounded,
                  label: 'play'.tr,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _play();
                  }),
              RiffQuickAction(
                  icon: Icons.shuffle_rounded,
                  label: 'shuffle'.tr,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _play(shuffle: true);
                  }),
              RiffQuickAction(
                  icon: Icons.sensors_rounded,
                  label: 'startRadio'.tr,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _play(radio: true);
                  }),
            ]),
            RiffSheetTile(
              icon: Icons.person_outline_rounded,
              title: 'viewArtist'.tr,
              onTap: () {
                Navigator.of(ctx).pop();
                _open();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
      onTap: _open,
      onLongPress: () => _actions(context),
      child: Column(
        children: [
          ClipOval(
            child: ImageWidget(size: size, artist: artist),
          ),
          const SizedBox(height: 10),
          Text(
            '${artist.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: homeCardTitleStyle(context),
          ),
          Text(
            'artist'.tr,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: homeCardSubtitleStyle(context),
          ),
        ],
      ),
    );
  }
}

/// Spotify-like pinned tiles: Liked Songs + Recently played (play on tap).
class _LibraryPinnedRow extends StatelessWidget {
  const _LibraryPinnedRow();

  int _count(String boxName) {
    if (!Hive.isBoxOpen(boxName)) return 0;
    return Hive.box(boxName).length;
  }

  void _open(String id, String title) {
    final pl = Playlist(
      title: title,
      playlistId: id,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    );
    Get.toNamed(
      ScreenNavigationSetup.playlistScreen,
      id: ScreenNavigationSetup.id,
      arguments: [pl, id],
    );
  }

  Future<void> _play(String id, String title, {bool shuffle = false}) async {
    if (!Hive.isBoxOpen(id) || Hive.box(id).isEmpty) {
      _open(id, title);
      return;
    }
    final tracks = <MediaItem>[];
    for (final raw in Hive.box(id).values) {
      try {
        final item = MediaItemBuilder.fromJson(raw);
        if (item.id.isNotEmpty) tracks.add(item);
      } catch (_) {}
    }
    if (tracks.isEmpty) {
      _open(id, title);
      return;
    }
    if (shuffle) {
      tracks.shuffle();
    } else if (id == 'LIBRP') {
      final ok = await Get.find<PlayerController>().playPlayListSong(
          tracks.reversed.toList(), 0,
          source: sourceFromPlaylistId(id));
      if (!ok) _snackPlayFailed();
      return;
    }
    final ok = await Get.find<PlayerController>()
        .playPlayListSong(tracks, 0, source: sourceFromPlaylistId(id));
    if (!ok) _snackPlayFailed();
  }

  void _showRecentsActions(BuildContext context) {
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
                _play('LIBRP', 'recentlyPlayed'.tr);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: Text('shuffle'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _play('LIBRP', 'recentlyPlayed'.tr, shuffle: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : theme.textTheme.bodySmall?.color;
    final liked = _count('LIBFAV');
    final recent = _count('LIBRP');
    final row = Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.sm,
          right: HomeLayout.gutter),
      child: Row(
        children: [
          Expanded(
            child: _PinnedTile(
              icon: Icons.favorite,
              title: 'favorites'.tr,
              subtitle: liked > 0 ? '$liked' : null,
              accent: theme.colorScheme.secondary,
              muted: muted,
              onTap: () => _open('LIBFAV', 'favorites'.tr),
              onLongPress: () => _play('LIBFAV', 'favorites'.tr, shuffle: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PinnedTile(
              icon: Icons.history,
              title: 'recentlyPlayed'.tr,
              subtitle: recent > 0 ? '$recent' : null,
              accent: theme.colorScheme.secondary,
              muted: muted,
              onTap: () => _open('LIBRP', 'recentlyPlayed'.tr),
              onLongPress: () => _showRecentsActions(context),
            ),
          ),
        ],
      ),
    );
    if (!SpotifyAuthService.isConnected) return row;
    // Signed in to Spotify: the library is one tap away.
    return Column(children: [
      row,
      Padding(
        padding: const EdgeInsets.only(
            left: HomeLayout.gutter,
            top: RiffSpacing.sm,
            right: HomeLayout.gutter),
        child: _PinnedTile(
          icon: Icons.library_music_outlined,
          title: 'Spotify',
          subtitle: 'spotifyLibraryTile'.tr,
          accent: theme.colorScheme.secondary,
          muted: muted,
          onTap: () => Get.toNamed(ScreenNavigationSetup.spotifyBridgeScreen,
              id: ScreenNavigationSetup.id),
          onLongPress: () => openSpotifyPage(const SpotifySearchArgs()),
        ),
      ),
    ]);
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
    this.subtitle,
    this.muted,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final Color? muted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).brightness == Brightness.dark
        ? RiffSurfaces.elevatedSoft
        : Theme.of(context).cardColor;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardTitleStyle(context),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
              Icon(Icons.play_circle_fill, color: accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

void _snackPlayFailed() => snackOperationFailed();
