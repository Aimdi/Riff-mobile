import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/models/playling_from.dart';
import '/services/cloud_music_service.dart';
import '/services/device_music.dart';
import '/services/discovery/discovery_tag.dart';
import '/services/discovery/discovery_types.dart';
import '/services/spotify_auth_service.dart';
import '/services/library_view_mode.dart';
import '/services/playlist_folders.dart';
import '/ui/screens/Plugins/spotify_pages.dart';
import '../../navigator.dart';
import '../../player/play_queue_order.dart';
import '../../player/library_list_source.dart';
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
import '../../widgets/riff_motion.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/shimmer_widgets/reveal.dart';
import '../../widgets/shimmer_widgets/skeleton_fade.dart';
import '../../widgets/shimmer_widgets/song_list_shimmer.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/sort_widget.dart';
import '../Cloud/cloud_play.dart';
import '../Cloud/cloud_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '../../theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_empty_state.dart';
import 'library_controller.dart';
import 'library_pins.dart';
import 'playlist_folder_ui.dart';
import '/ui/theme/riff_text_metrics.dart';
import '/ui/widgets/riff_header_bar.dart';

class SongsLibraryWidget extends StatelessWidget {
  const SongsLibraryWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = riffTabTop(context);
    final libSongsController = Get.find<LibrarySongsController>();
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() {
            final cloudMode = libSongsController.showCloudSongs.value;
            final deviceMode = libSongsController.showDeviceSongs.value;
            final canPlay = deviceMode
                ? libSongsController.deviceSongs.isNotEmpty
                : shouldShowLibrarySongsPlayBar(
                    cloudMode: cloudMode,
                    songCount: libSongsController.visibleSongs.length,
                  );
            return LibraryHeader(
              title: deviceMode
                  ? "onThisPhone".tr
                  : cloudMode
                      ? "cloud".tr
                      : "libSongs".tr,
              actions: [
                if (canPlay) ...[
                  IconButton(
                    tooltip: 'shuffle'.tr,
                    icon: const Icon(Icons.shuffle_rounded),
                    onPressed: () => deviceMode
                        ? _playDeviceSongs(shuffle: true)
                        : _playLibrarySongs(shuffle: true),
                  ),
                  LibraryPlayButton(
                      onPressed: () => deviceMode
                          ? _playDeviceSongs()
                          : _playLibrarySongs(shuffle: false)),
                ],
              ],
            );
          }),
          const _LibraryPinnedRow(),
          Obx(() {
            final cloudMode = libSongsController.showCloudSongs.value;
            final deviceMode = libSongsController.showDeviceSongs.value;
            final cloud = Get.find<CloudMusicService>();
            final downloadedOnly = libSongsController.downloadedOnly.value;
            final count = deviceMode
                ? libSongsController.deviceSongs.length
                : cloudMode
                    ? (cloud.isConnected.value ? cloud.songs.length : 0)
                    : libSongsController.visibleSongs.length;
            // The library's own songs: what search, sort and the rest act on.
            final libraryMode = !cloudMode && !deviceMode;
            return SortWidget(
              tag: LibrarySortTags.songs,
              screenController: libSongsController,
              itemCountTitle: "$count",
              itemIcon: Icons.music_note,
              requiredSortTypes: {
                ...buildSortTypeSet(true, true),
                ...songOrderSortTypes,
              },
              isSearchFeatureRequired: libraryMode,
              isSongDeletetioFeatureRequired: libraryMode,
              isDownloadedFilterRequired: libraryMode,
              isDownloadedOnly: downloadedOnly,
              onDownloadedToggle: libSongsController.toggleDownloadedOnly,
              isCloudFeatureRequired: true,
              isCloudModeActive: cloudMode,
              onCloudToggle: () => libSongsController.toggleCloudSongs(),
              isDeviceFeatureRequired: DeviceMusic.available,
              isDeviceModeActive: deviceMode,
              onDeviceToggle: () => libSongsController.toggleDeviceSongs(),
              // The library's songs and the phone's, not the cloud's.
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
          Expanded(
            child: RiffScrollUnder(child: Obx(() {
              // The library's songs, the phone's and the cloud's crossfade
              // as the toolbar switches between them.
              final String pane;
              final Widget child;
              if (libSongsController.showDeviceSongs.value) {
                pane = 'device';
                child = const _DeviceSongsPane();
              } else if (libSongsController.showCloudSongs.value) {
                pane = 'cloud';
                child = const _CloudSongsPane();
              } else {
                pane = 'library';
                child = GetX<LibrarySongsController>(builder: (controller) {
                  final songs = controller.visibleSongs;
                  if (controller.downloadedOnly.isTrue &&
                      songs.isEmpty &&
                      controller.librarySongsList.isNotEmpty) {
                    return EmptyPlayHint(message: "noDownloadedSongs".tr);
                  }
                  // The list and its selection mode crossfade.
                  return songs.isNotEmpty
                      ? RiffPaneSwitcher(
                          child: controller.additionalOperationMode.value ==
                                  OperationMode.none
                              // ListWidget returns an Expanded, so it needs a
                              // Flex parent (it sat directly in this Expanded
                              // before: "Incorrect use of ParentDataWidget").
                              ? Padding(
                                  key: const ValueKey('list'),
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Column(
                                    children: [
                                      ListWidget(
                                        songs,
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
                                  key: const ValueKey('selecting'),
                                  mode:
                                      controller.additionalOperationMode.value,
                                  screenController: controller,
                                ))
                      : EmptyPlayHint(message: "noOfflineSong".tr);
                });
              }
              return RiffPaneSwitcher(
                  child: KeyedSubtree(key: ValueKey(pane), child: child));
            })),
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
  final songs = Get.find<LibrarySongsController>().visibleSongs;
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

/// Plays the phone's music files, from [from] or shuffled.
Future<void> _playDeviceSongs({int from = 0, bool shuffle = false}) async {
  if (!Get.isRegistered<LibrarySongsController>() ||
      !Get.isRegistered<PlayerController>()) {
    return;
  }
  final songs = Get.find<LibrarySongsController>().deviceSongs.toList();
  if (songs.isEmpty) return;
  final ok = await Get.find<PlayerController>().playPlayListSong(
    shuffle ? playQueueFrom(songs, shuffle: true) : songs,
    shuffle ? 0 : from,
    playfrom: PlaylingFrom(
      type: PlaylingFromType.SELECTION,
      name: 'onThisPhone'.tr,
    ),
    source: DiscoverySource.downloads,
  );
  if (!ok) _snackPlayFailed();
}

/// Songs › On this phone: the phone's music files, once Android lets Riff
/// read them.
class _DeviceSongsPane extends StatelessWidget {
  const _DeviceSongsPane();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LibrarySongsController>();
    return Obx(() {
      final songs = controller.deviceSongs.toList();
      final Widget? content;
      if (controller.deviceAccess.value == false) {
        content = PodcastEmptyState(
          icon: Icons.phone_android_outlined,
          message: 'deviceMusicAccess'.tr,
          actionLabel: 'allowAccess'.tr,
          actionIcon: Icons.lock_open_rounded,
          onAction: () => controller.loadDeviceSongs(settings: true),
        );
      } else if (songs.isEmpty) {
        content = controller.deviceLoading.isTrue
            ? null
            : PodcastEmptyState(
                icon: Icons.phone_android_outlined,
                message: 'noDeviceSongs'.tr,
              );
      } else {
        content = ListView.builder(
          padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
          itemExtent: RiffComponentSizes.songRowExtent,
          itemCount: songs.length,
          itemBuilder: (context, i) => SongListTile(
            key: ValueKey(songs[i].id),
            song: songs[i],
            onTap: () => _playDeviceSongs(from: i),
          ),
        );
      }
      // The songs fade in where the skeleton was.
      return SkeletonFadeIn(
        skeleton:
            const SongListShimmer(itemCount: 8, topPadding: RiffSpacing.md),
        child: content,
      );
    });
  }
}

/// A rail tab's title row: the page's name as large as Home's greeting
/// (Apple Music's and Spotify's page titles), actions on the right.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader(
      {super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return RiffHeaderBar(
        hairline: false,
        child: Padding(
          padding: const EdgeInsets.only(
              left: HomeLayout.gutter,
              right: RiffSpacing.sm,
              bottom: RiffSpacing.xxs),
          child: SizedBox(
            height: RiffSpacing.headerRow,
            child: Row(
              children: [
                Expanded(child: RiffPageTitle(title)),
                ...actions,
              ],
            ),
          ),
        ));
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

/// Library grid for the pane [width]: 2 columns of large covers on
/// phones (Apple Music's album grid), more on tablets, covers sized to
/// fill each column.
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

/// Artists grid: smaller circles than the album grid, one more column (3
/// on phones, as Spotify's grid of artists).
({int columns, double cover}) libraryArtistGridMetrics(double width) {
  final columns = width >= 1100
      ? 7
      : width >= 720
          ? 5
          : width >= 300
              ? 3
              : 2;
  final cover =
      (width - HomeLayout.gutter * 2 - HomeLayout.cardGap * (columns - 1)) /
          columns;
  return (columns: columns, cover: cover);
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
      // The songs fade in where the skeleton was.
      return SkeletonFadeIn(
        skeleton: const SongListShimmer(itemCount: 8, topPadding: 12),
        child: cloud.isLoading.value && cloud.songs.isEmpty
            ? null
            : _songs(context, cloud),
      );
    });
  }

  Widget _songs(BuildContext context, CloudMusicService cloud) {
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
  }
}

class PlaylistNAlbumLibraryWidget extends StatefulWidget {
  const PlaylistNAlbumLibraryWidget({super.key, this.isAlbumContent = true});
  final bool isAlbumContent;

  @override
  State<PlaylistNAlbumLibraryWidget> createState() =>
      _PlaylistNAlbumLibraryWidgetState();
}

class _PlaylistNAlbumLibraryWidgetState
    extends State<PlaylistNAlbumLibraryWidget> {
  // One controller for the grid's lifetime — it used to be created inside
  // build (Obx/LayoutBuilder), leaking a controller on every rebuild.
  final _gridScroll = ScrollController(keepScrollOffset: false);

  /// The layout last shown (list or grid), so switching it fades the new
  /// one in, but opening the tab doesn't.
  bool? _shownAsList;

  bool get isAlbumContent => widget.isAlbumContent;

  @override
  void dispose() {
    _gridScroll.dispose();
    super.dispose();
  }

  /// What the tab lists: the albums, or the playlists with their folders
  /// (playlists in a folder show in it, not here).
  List<Object> _items(
      LibraryAlbumsController albums, LibraryPlaylistsController playlists) {
    if (isAlbumContent) return albums.libraryAlbums;
    PlaylistFolders.rev.value;
    return libraryPlaylistItems(
        playlists.libraryPlaylists, PlaylistFolders.folders,
        leading: (id) =>
            isSystemLibraryPlaylistId(id) || LibraryPins.isPinned(id),
        searching: playlists.tempListContainer.isNotEmpty);
  }

  /// One of [_items]: a folder's tile, or the album or playlist.
  Widget _item(Object item, LibraryPlaylistsController playlists,
          {required double size, bool asRow = false}) =>
      item is PlaylistFolder
          ? PlaylistFolderTile(
              folder: item,
              count: folderPlaylists(item, playlists.libraryPlaylists).length,
              size: size,
              asRow: asRow,
            )
          : ContentListItem(
              content: item,
              isLibraryItem: true,
              size: size,
              asRow: asRow,
            );

  /// The list view: one row per album, playlist or folder.
  Widget _list(
      LibraryAlbumsController albums, LibraryPlaylistsController playlists) {
    final items = _items(albums, playlists);
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(
          top: RiffSpacing.xs, bottom: RiffSpacing.listEnd),
      controller: _gridScroll,
      itemCount: items.length,
      itemBuilder: (context, index) => _item(items[index], playlists,
          size: RiffComponentSizes.rowArt, asRow: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libralbumCntrller = Get.find<LibraryAlbumsController>();
    final librplstCntrller = Get.find<LibraryPlaylistsController>();
    final settingscrnController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;

    final topPadding = riffTabTop(context);

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          LibraryHeader(
            title: isAlbumContent ? "libAlbums".tr : "libPlaylists".tr,
            actions: [
              if (!isAlbumContent &&
                  settingscrnController.isLinkedWithPiped.isTrue)
                PipedSyncWidget(
                  padding: EdgeInsets.only(right: size.width * .02),
                ),
              // Grid or list, as Spotify's Your Library switches.
              Obx(() {
                final list = LibraryViewMode.list.isTrue;
                return IconButton(
                  tooltip: (list ? 'showAsGrid' : 'showAsList').tr,
                  icon: RiffSwitcher(
                    child: Icon(
                        list
                            ? Icons.grid_view_rounded
                            : Icons.view_list_rounded,
                        key: ValueKey(list)),
                  ),
                  onPressed: () => LibraryViewMode.setList(!list),
                );
              }),
            ],
          ),
          Obx(
            () => isAlbumContent
                ? SortWidget(
                    tag: LibrarySortTags.albums,
                    screenController: libralbumCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${libralbumCntrller.libraryAlbums.length} ${"items".tr}",
                    requiredSortTypes: {
                      ...buildSortTypeSet(true, false, true),
                      SortType.Artist,
                    },
                    onSort: (type, ascending) {
                      libralbumCntrller.onSort(type, ascending);
                    },
                    onSearch: libralbumCntrller.onSearch,
                    onSearchClose: libralbumCntrller.onSearchClose,
                    onSearchStart: libralbumCntrller.onSearchStart,
                  )
                : SortWidget(
                    tag: LibrarySortTags.playlists,
                    screenController: librplstCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${librplstCntrller.libraryPlaylists.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(false, false, true),
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
            child: RiffScrollUnder(child: Obx(() {
              // Folders change what the playlists are listed with (read
              // here: the grid's builder runs outside this Obx).
              PlaylistFolders.rev.value;
              // Still reading the library: neither the albums nor "no
              // albums" yet (the empty message used to flash first).
              if (isAlbumContent &&
                  libralbumCntrller.isContentFetched.isFalse) {
                return const SizedBox.shrink();
              }
              final asList = LibraryViewMode.list.isTrue;
              final switched = _shownAsList != null && _shownAsList != asList;
              _shownAsList = asList;
              return (isAlbumContent
                      ? libralbumCntrller.libraryAlbums.isNotEmpty
                      : librplstCntrller.libraryPlaylists.isNotEmpty)
                  // Grid and list share the scroll controller, so the new
                  // layout fades in in place of the old (no crossfade).
                  ? RiffFadeIn(
                      key: ValueKey(asList),
                      duration:
                          switched ? RiffDurations.content : Duration.zero,
                      rise: 0,
                      child: asList
                          ? _list(libralbumCntrller, librplstCntrller)
                          : LayoutBuilder(builder: (context, constraints) {
                              final grid =
                                  libraryGridMetrics(constraints.maxWidth);
                              final items =
                                  _items(libralbumCntrller, librplstCntrller);
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
                                    mainAxisExtent: ContentListItem.heightFor(
                                        context, grid.cover),
                                  ),
                                  controller: _gridScroll,
                                  itemCount: items.length,
                                  itemBuilder:
                                      (BuildContext context, int index) =>
                                          _item(items[index], librplstCntrller,
                                              size: grid.cover));
                            }))
                  : EmptyPlayHint(
                      message: isAlbumContent
                          ? "noLibAlbums".tr
                          : "noLibPlaylist".tr);
            })),
          )
        ],
      ),
    );
  }
}

class LibraryArtistWidget extends StatelessWidget {
  const LibraryArtistWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final cntrller = Get.find<LibraryArtistsController>();
    final topPadding = riffTabTop(context);
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          LibraryHeader(title: "libArtists".tr),
          Obx(
            () => SortWidget(
              tag: LibrarySortTags.artists,
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
            child: RiffScrollUnder(
                child: Obx(() => cntrller.isContentFetched.isFalse
                    // Still reading the library: no "no artists" flash.
                    ? const SizedBox.shrink()
                    : cntrller.libraryArtists.isEmpty
                        ? EmptyPlayHint(message: "noLibArtists".tr)
                        : LayoutBuilder(builder: (context, constraints) {
                            final grid =
                                libraryArtistGridMetrics(constraints.maxWidth);
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
                                mainAxisSpacing: RiffSpacing.lg,
                                mainAxisExtent: grid.cover +
                                    RiffSpacing.sm +
                                    riffLineHeight(
                                        context, homeCardTitleStyle(context)),
                              ),
                              itemCount: cntrller.libraryArtists.length,
                              itemBuilder: (context, index) =>
                                  _LibraryArtistCard(
                                artist: cntrller.libraryArtists[index],
                                size: grid.cover,
                              ),
                            );
                          }))),
          ),
        ],
      ),
    );
  }
}

/// Round artist card: photo and name (the tab already says they're
/// artists). Tap opens the artist; long-press offers play, shuffle, radio
/// and open.
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
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
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
            const SizedBox(height: RiffSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${artist.name}, ${'artist'.tr}',
      excludeSemantics: true,
      child: RiffPressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
          onTap: _open,
          onLongPress: () => _actions(context),
          child: Column(
            children: [
              ClipOval(
                child: ImageWidget(size: size, artist: artist),
              ),
              const SizedBox(height: RiffSpacing.sm),
              Text(
                '${artist.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: homeCardTitleStyle(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spotify-like pinned tiles: Liked Songs + Recently played. A tap opens
/// the list, a long press plays it or offers to (no play glyph: the tile
/// itself opens).
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
    // Where it comes from, as its own page plays it: the player says so.
    final from = PlaylingFrom(
        type: PlaylingFromType.PLAYLIST,
        name: title,
        id: id,
        item: libraryOwnList(id) ??
            Playlist(
                title: title,
                playlistId: id,
                thumbnailUrl: Playlist.thumbPlaceholderUrl,
                isCloudPlaylist: false));
    if (shuffle) {
      tracks.setAll(0, playQueueFrom(tracks, shuffle: true));
    } else if (id == 'LIBRP') {
      final ok = await Get.find<PlayerController>().playPlayListSong(
          tracks.reversed.toList(), 0,
          playfrom: from, source: sourceFromPlaylistId(id));
      if (!ok) _snackPlayFailed();
      return;
    }
    final ok = await Get.find<PlayerController>().playPlayListSong(tracks, 0,
        playfrom: from, source: sourceFromPlaylistId(id));
    if (!ok) _snackPlayFailed();
  }

  void _showRecentsActions(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        // Sheet rows per RIFF_UI_RESTYLE.md §5.10.
        child: ListTileTheme.merge(
          titleTextStyle: Theme.of(ctx).textTheme.bodyLarge,
          iconColor: Theme.of(ctx).colorScheme.onSurface,
          child: IconTheme.merge(
            data: const IconThemeData(size: RiffComponentSizes.headerIcon),
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
            ],
          ),
        ),
      ),
    );
  }
}

void _snackPlayFailed() => snackOperationFailed();
