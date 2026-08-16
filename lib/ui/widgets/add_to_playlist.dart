import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../services/discovery/discovery_service.dart';
import '../../services/downloader.dart';
import '../../services/piped_service.dart';
import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/screens/Playlist/playlist_screen_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/sheet_insets.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../models/playlist.dart';
import 'common_dialog_widget.dart';
import 'snackbar.dart';

/// Built-in library playlists that are not user-created add targets.
const systemLibraryPlaylistIds = {
  'LIBFAV',
  'LIBRP',
  'SongsCache',
  'SongDownloads',
};

bool isSystemLibraryPlaylistId(String id) =>
    systemLibraryPlaylistIds.contains(id);

/// User playlists for the add sheet. [LIBFAV] is pinned separately.
List<Playlist> userPlaylistsForAddSheet({List<Playlist>? fromLibrary}) {
  if (fromLibrary != null) {
    return fromLibrary
        .where((p) => !isSystemLibraryPlaylistId(p.playlistId))
        .toList();
  }
  if (Get.isRegistered<LibraryPlaylistsController>()) {
    return Get.find<LibraryPlaylistsController>()
        .libraryPlaylists
        .where((p) => !isSystemLibraryPlaylistId(p.playlistId))
        .toList();
  }
  if (Get.isRegistered<AddToPlaylistController>()) {
    return Get.find<AddToPlaylistController>().playlists.toList();
  }
  return const [];
}

BuildContext? safeAddToPlaylistContext(BuildContext? context) {
  if (context != null && context.mounted) return context;
  if (Get.isRegistered<PlayerController>()) {
    final home =
        Get.find<PlayerController>().homeScaffoldkey.currentContext;
    if (home != null && home.mounted) return home;
  }
  final fallback = Get.context;
  if (fallback != null && fallback.mounted) return fallback;
  return null;
}

/// Spotify-like 1–2 tap add-to-playlist. Preferred over [AddToPlaylist].
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  List<MediaItem> songs,
) async {
  if (songs.isEmpty) return;
  final sheetContext = safeAddToPlaylistContext(context);
  if (sheetContext == null) return;
  await showModalBottomSheet<void>(
    context: sheetContext,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 500),
    backgroundColor: Theme.of(sheetContext).cardColor,
    barrierColor: Colors.transparent.withAlpha(100),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RiffTokens.radiusSm),
      ),
    ),
    builder: (context) => AddToPlaylistSheet(songItems: songs),
  );
  if (Get.isRegistered<AddToPlaylistController>()) {
    Get.delete<AddToPlaylistController>();
  }
}

Future<bool> addSongsToLikedSongs(List<MediaItem> songs) async {
  final box = Hive.isBoxOpen('LIBFAV')
      ? Hive.box('LIBFAV')
      : await Hive.openBox('LIBFAV');
  var addedAny = false;
  for (final song in songs) {
    if (box.containsKey(song.id)) continue;
    await box.put(song.id, MediaItemBuilder.toJson(song));
    addedAny = true;
    if (Get.isRegistered<DiscoveryService>()) {
      Get.find<DiscoveryService>().onFavorite(song, add: true);
    }
    if (Get.isRegistered<SettingsScreenController>() &&
        Get.find<SettingsScreenController>()
            .autoDownloadFavoriteSongEnabled
            .isTrue &&
        Get.isRegistered<Downloader>()) {
      Get.find<Downloader>().download(song);
    }
    try {
      final playlistController = Get.find<PlaylistScreenController>(
          tag: const Key('LIBFAV').hashCode.toString());
      playlistController.addNRemoveItemsinList(song, action: 'add', index: 0);
    } catch (_) {}
  }
  if (Get.isRegistered<PlayerController>()) {
    final player = Get.find<PlayerController>();
    final current = player.currentSong.value;
    if (current != null) {
      player.isCurrentSongFav.value = box.containsKey(current.id);
    }
  }
  return addedAny;
}

class AddToPlaylistSheet extends StatefulWidget {
  const AddToPlaylistSheet({
    super.key,
    required this.songItems,
    this.playlistsOverride,
  });

  final List<MediaItem> songItems;
  final List<Playlist>? playlistsOverride;

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  bool _busy = false;

  AddToPlaylistController _controller() {
    if (Get.isRegistered<AddToPlaylistController>()) {
      return Get.find<AddToPlaylistController>();
    }
    return Get.put(AddToPlaylistController());
  }

  void _snack(String message) {
    final messengerContext = safeAddToPlaylistContext(Get.context);
    if (messengerContext == null) return;
    ScaffoldMessenger.of(messengerContext).showSnackBar(
      snackbar(messengerContext, message, size: SanckBarSize.MEDIUM),
    );
  }

  Future<void> _finish(bool added) async {
    if (!mounted) return;
    Navigator.of(context).pop();
    _snack(added ? 'songAddedToPlaylistAlert'.tr : 'songAlreadyExists'.tr);
    if (added && Get.isRegistered<DiscoveryService>()) {
      for (final song in widget.songItems) {
        Get.find<DiscoveryService>().onPlaylistAdd(song);
      }
    }
  }

  Future<void> _addToLiked() async {
    if (_busy) return;
    setState(() => _busy = true);
    final added = await addSongsToLikedSongs(widget.songItems);
    await _finish(added);
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = _controller();
    controller.playlistType.value =
        playlist.isPipedPlaylist ? 'piped' : 'local';
    final added = await controller.addSongsToPlaylist(
      widget.songItems,
      playlist.playlistId,
      context,
    );
    await _finish(added);
  }

  void _createPlaylist() {
    if (_busy) return;
    Navigator.of(context).pop();
    final createContext = safeAddToPlaylistContext(Get.context);
    if (createContext == null) return;
    showDialog(
      context: createContext,
      builder: (context) => CreateNRenamePlaylistPopup(
        isCreateNadd: true,
        songItems: widget.songItems,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark
        ? RiffSurfaces.textMuted
        : theme.textTheme.titleSmall?.color?.withOpacity(0.65);
    return Padding(
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context, liftAboveMiniPlayer: false),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: (isDark ? RiffSurfaces.hairline : theme.dividerColor)
                  .withOpacity(0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'addToPlaylist'.tr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          _SheetRow(
            leading: _SheetIcon(
              icon: Icons.favorite,
              color: theme.colorScheme.secondary,
            ),
            title: 'favorites'.tr,
            muted: muted,
            onTap: _addToLiked,
          ),
          _SheetRow(
            leading: _SheetIcon(
              icon: Icons.add,
              color: theme.colorScheme.onSurface,
            ),
            title: 'CreateNewPlaylist'.tr,
            muted: muted,
            onTap: _createPlaylist,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.48,
            ),
            child: _playlistList(muted),
          ),
        ],
      ),
    );
  }

  Widget _playlistList(Color? muted) {
    if (widget.playlistsOverride != null) {
      return _playlistTiles(
        userPlaylistsForAddSheet(fromLibrary: widget.playlistsOverride),
        muted,
      );
    }
    if (Get.isRegistered<LibraryPlaylistsController>()) {
      return Obx(() => _playlistTiles(userPlaylistsForAddSheet(), muted));
    }
    _controller();
    return Obx(
      () => _playlistTiles(
        Get.find<AddToPlaylistController>().playlists.toList(),
        muted,
      ),
    );
  }

  Widget _playlistTiles(List<Playlist> playlists, Color? muted) {
    if (playlists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'noLibPlaylist'.tr,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: muted,
                ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _SheetRow(
          leading: _SheetIcon(
            icon: playlist.isPipedPlaylist
                ? Icons.cloud_outlined
                : Icons.playlist_play,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          title: playlist.title,
          muted: muted,
          onTap: () => _addToPlaylist(playlist),
        );
      },
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.muted,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Color? muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.15,
            ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: muted,
                  ),
            ),
      onTap: onTap,
    );
  }
}

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? RiffSurfaces.elevatedSoft : Theme.of(context).primaryColorLight,
        borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class AddToPlaylist extends StatelessWidget {
  const AddToPlaylist(this.songItems, {super.key});
  final List<MediaItem> songItems;

  @override
  Widget build(BuildContext context) {
    final addToPlaylistController = Get.put(AddToPlaylistController());
    final isPipedLinked = Get.find<PipedServices>().isLoggedIn;
    return CommonDialog(
      child: Container(
        height: isPipedLinked ? 400 : 350,
        padding:
            const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            Column(children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10.0, top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Marquee(
                          id:"createNewPlaylistx",
                          delay: const Duration(milliseconds: 300),
                          child: Text(
                            "CreateNewPlaylist".tr,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10,),
                    InkWell(
                      child: const Icon(Icons.playlist_add),
                      onTap: () {
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (context) => CreateNRenamePlaylistPopup(
                              isCreateNadd: true, songItems: songItems),
                        );
                      },
                    )
                  ],
                ),
              ),
              if (isPipedLinked)
                Obx(
                  () => Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Radio(
                              value: "piped",
                              groupValue:
                                  addToPlaylistController.playlistType.value,
                              onChanged:
                                  addToPlaylistController.changePlaylistType),
                          Text("Piped".tr),
                        ],
                      ),
                      const SizedBox(
                        width: 15,
                      ),
                      Row(
                        children: [
                          Radio(
                              value: "local",
                              groupValue:
                                  addToPlaylistController.playlistType.value,
                              onChanged:
                                  addToPlaylistController.changePlaylistType),
                          Text("local".tr),
                        ],
                      )
                    ],
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                    color: Theme.of(context).primaryColorLight,
                    borderRadius: BorderRadius.circular(10)),
                height: 250,
                //color: Colors.green,
                child: Obx(
                  () => addToPlaylistController.playlists.isNotEmpty
                      ? ListView.builder(
                          itemCount: addToPlaylistController.playlists.length,
                          itemBuilder: (context, index) => ListTile(
                            leading: const Icon(Icons.playlist_play),
                            title: Text(
                              (addToPlaylistController.playlists[index]).title,
                            ),
                            onTap: () {
                              addToPlaylistController
                                  .addSongsToPlaylist(
                                      songItems,
                                      (addToPlaylistController.playlists[index])
                                          .playlistId,
                                      context)
                                  .then((value) {
                                if (!context.mounted) return;
                                if (value) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context,
                                          "songAddedToPlaylistAlert".tr,
                                          size: SanckBarSize.MEDIUM));
                                  Navigator.of(context).pop();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context, "songAlreadyExists".tr,
                                          size: SanckBarSize.MEDIUM));
                                  Navigator.of(context).pop();
                                }
                              });
                            },
                          ),
                        )
                      : Center(
                          child: Text("noLibPlaylist".tr),
                        ),
                ),
              )
            ]),
            Obx(() => (addToPlaylistController.additionInProgress.isTrue &&
                    isPipedLinked)
                ? const Positioned(
                    top: 60,
                    right: 8,
                    child: SizedBox(
                        height: 15,
                        width: 15,
                        child: CircularProgressIndicator(
                          backgroundColor: Colors.transparent,
                          strokeWidth: 2,
                        )),
                  )
                : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class AddToPlaylistController extends GetxController {
  final RxList<Playlist> playlists = RxList();
  final playlistType = "local".obs;
  final additionInProgress = false.obs;
  List<Playlist> localPlaylists = [];
  List<Playlist> pipedPlaylists = [];
  AddToPlaylistController() {
    _getAllPlaylist();
  }

  Future<void> _getAllPlaylist() async {
    final plstsBox = await Hive.openBox("LibraryPlaylists");
    playlists.value = plstsBox.values
        .map((e) {
          if (!e["isCloudPlaylist"]) return Playlist.fromJson(e);
        })
        .whereType<Playlist>()
        .toList();
    localPlaylists = playlists.toList();
    final res = await Get.find<PipedServices>().getAllPlaylists();
    if (res.code == 1) {
      pipedPlaylists = res.response
          .map((item) => Playlist(
                title: item['name'],
                playlistId: item['id'],
                description: "Piped Playlist",
                thumbnailUrl: item['thumbnail'],
                isPipedPlaylist: true,
              ))
          .whereType<Playlist>()
          .toList();
    }
  }

  void changePlaylistType(val) {
    playlistType.value = val;
    playlists.value = val == "piped" ? pipedPlaylists : localPlaylists;
  }

  Future<bool> addSongsToPlaylist(
      List<MediaItem> songs, String playlistId, BuildContext context) async {
    additionInProgress.value = true;
    if (playlistType.value == "local") {
      final plstBox = await Hive.openBox(playlistId);
      final playlistSongIds = plstBox.values.map((item) => item['videoId']);
      for (MediaItem element in songs) {
        if (!playlistSongIds.contains(element.id)) {
          await plstBox.add(MediaItemBuilder.toJson(element));
        }
      }
      await plstBox.close();
      additionInProgress.value = false;
      return true;
    } else {
      final videosId = songs.map((e) => e.id).toList();
      final res =
          await Get.find<PipedServices>().addToPlaylist(playlistId, videosId);
      additionInProgress.value = false;
      return (res.code == 1);
    }
  }

  // Future<bool> addSongToPlaylist(
  //     MediaItem song, String playlistId, BuildContext context) async {
  //   if (playlistType.value == "local") {
  //     final plstBox = await Hive.openBox(playlistId);
  //     if (!plstBox.containsKey(song.id)) {
  //       plstBox.put(song.id, MediaItemBuilder.toJson(song));
  //       plstBox.close();
  //       return true;
  //     } else {
  //       plstBox.close();
  //       return false;
  //     }
  //   } else {
  //     additionInProgress.value = true;

  //     final res =
  //         await Get.find<PipedServices>().addToPlaylist(playlistId, song.id);
  //     additionInProgress.value = false;
  //     return (res.code == 1);
  //   }
  // }
}
