import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/models/playling_from.dart';
import '/services/cloud_music_service.dart';
import '../../navigator.dart';
import '../../player/play_queue_order.dart';
import '../../player/player_controller.dart';
import '../../utils/riff_tokens.dart';
import '../../utils/theme_controller.dart';
import '../../widgets/modification_list.dart';
import '../../widgets/piped_sync_widget.dart';
import '../../widgets/content_list_widget_item.dart';
import '../../widgets/empty_play_hint.dart';
import '../../widgets/list_widget.dart';
import '../../widgets/sort_widget.dart';
import '../Cloud/cloud_play.dart';
import '../Cloud/cloud_screen.dart';
import '../Settings/settings_screen_controller.dart';
import 'library_controller.dart';

class SongsLibraryWidget extends StatelessWidget {
  const SongsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    final libSongsController = Get.find<LibrarySongsController>();
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5.0, top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isBottomNavActive
              ? const SizedBox(
                  height: 10,
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Obx(() {
                    final cloudMode = libSongsController.showCloudSongs.value;
                    return Text(
                      cloudMode ? "cloud".tr : "libSongs".tr,
                      style: Theme.of(context).textTheme.titleLarge,
                    );
                  }),
                ),
          if (!isBottomNavActive) const _LibraryPinnedRow(),
          Obx(() {
            final cloudMode = libSongsController.showCloudSongs.value;
            final cloud = Get.find<CloudMusicService>();
            final count = cloudMode
                ? (cloud.isConnected.value
                    ? cloud.songs.length
                    : 0)
                : libSongsController.librarySongsList.length;
            return SortWidget(
              tag: "LibSongSort",
              screenController: libSongsController,
              itemCountTitle: "$count",
              itemIcon: Icons.music_note,
              titleLeftPadding: 9,
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
                        ? ListWidget(
                            controller.librarySongsList,
                            "library Songs",
                            true,
                            isPlaylistOrAlbum: true,
                            playlist: Playlist(
                                title: "Library Songs",
                                playlistId: "SongDownloads",
                                thumbnailUrl: "",
                                isCloudPlaylist: false),
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

/// Play all / Shuffle for the offline Songs tab (Spotify library chrome).
class _LibrarySongsPlayBar extends StatelessWidget {
  const _LibrarySongsPlayBar();

  Future<void> _play({required bool shuffle}) async {
    if (!Get.isRegistered<LibrarySongsController>() ||
        !Get.isRegistered<PlayerController>()) {
      return;
    }
    final songs = Get.find<LibrarySongsController>().librarySongsList;
    if (songs.isEmpty) return;
    final queue = playQueueFrom(songs, shuffle: shuffle);
    await Get.find<PlayerController>().playPlayListSong(
      queue,
      0,
      playfrom: PlaylingFrom(
        type: PlaylingFromType.PLAYLIST,
        name: 'libSongs'.tr,
      ),
    );
  }

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
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 4),
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
        return const Center(child: CircularProgressIndicator());
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

class PlaylistNAlbumLibraryWidget extends StatelessWidget {
  const PlaylistNAlbumLibraryWidget(
      {super.key, this.isAlbumContent = true, this.isBottomNavActive = false});
  final bool isAlbumContent;
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final libralbumCntrller = Get.find<LibraryAlbumsController>();
    final librplstCntrller = Get.find<LibraryPlaylistsController>();
    final settingscrnController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;

    const double itemHeight = 180;
    const double itemWidth = 130;
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                isBottomNavActive
                    ? const SizedBox(
                        height: 10,
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isAlbumContent ? "libAlbums".tr : "libPlaylists".tr,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                (isAlbumContent ||
                        settingscrnController.isLinkedWithPiped.isFalse)
                    ? const SizedBox.shrink()
                    : PipedSyncWidget(
                        padding: EdgeInsets.only(right: size.width * .05),
                      )
              ],
            ),
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
                      //Fix for grid in mobile screen
                      final availableWidth = constraints.maxWidth > 300 &&
                              constraints.maxWidth < 394
                          ? 310.0
                          : constraints.maxWidth;
                      int columns = (availableWidth / itemWidth).floor();
                      return SizedBox(
                        width: availableWidth,
                        child: GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 200),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              childAspectRatio: (itemWidth / itemHeight),
                            ),
                            controller: ScrollController(keepScrollOffset: false),
                            itemCount: isAlbumContent
                                ? libralbumCntrller.libraryAlbums.length
                                : librplstCntrller.libraryPlaylists.length,
                            itemBuilder: (BuildContext context, int index) {
                              return Center(
                                  child: ContentListItem(
                                content: isAlbumContent
                                    ? libralbumCntrller.libraryAlbums[index]
                                    : librplstCntrller.libraryPlaylists[index],
                                isLibraryItem: true,
                              ));
                            }),
                      );
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
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5, top: topPadding),
      child: Column(
        children: [
          isBottomNavActive
              ? const SizedBox(
                  height: 10,
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "libArtists".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
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
          Obx(() => cntrller.libraryArtists.isNotEmpty
              ? ListWidget(cntrller.libraryArtists, "Library Artists", true)
              : Expanded(
                  child: EmptyPlayHint(message: "noLibArtists".tr)))
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
      await Get.find<PlayerController>()
          .playPlayListSong(tracks.reversed.toList(), 0);
      return;
    }
    await Get.find<PlayerController>().playPlayListSong(tracks, 0);
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
              leading: const Icon(Icons.shuffle),
              title: Text('shuffle'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _play('LIBRP', 'recentlyPlayed'.tr, shuffle: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text('viewAll'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _open('LIBRP', 'recentlyPlayed'.tr);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _PinnedTile(
              icon: Icons.favorite,
              title: 'favorites'.tr,
              subtitle: liked > 0 ? '$liked' : null,
              accent: theme.colorScheme.secondary,
              muted: muted,
              onTap: () => _play('LIBFAV', 'favorites'.tr, shuffle: true),
              onLongPress: () => _open('LIBFAV', 'favorites'.tr),
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
              onTap: () => _play('LIBRP', 'recentlyPlayed'.tr),
              onLongPress: () => _showRecentsActions(context),
            ),
          ),
        ],
      ),
    );
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
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: muted, fontSize: 11),
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
