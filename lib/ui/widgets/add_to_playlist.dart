import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'riff_sheet.dart';
import 'package:hive/hive.dart';

import '../../services/discovery/discovery_service.dart';
import '../../services/downloader.dart';
import '../../services/piped_service.dart';
import '../../services/spotify_like_sync.dart';
import '../../services/yt_like_sync.dart';
import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/screens/Playlist/playlist_screen_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/utils/sheet_insets.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../models/playlist.dart';
import 'collection_play.dart' show isSystemLibraryPlaylistId;
import 'snackbar.dart';

/// Built-in library playlists (Favourites, Recently played, Cached,
/// Downloads) are not user-created add targets.
export 'collection_play.dart' show isSystemLibraryPlaylistId;

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
    final home = Get.find<PlayerController>().homeScaffoldkey.currentContext;
    if (home != null && home.mounted) return home;
  }
  final fallback = Get.context;
  if (fallback != null && fallback.mounted) return fallback;
  return null;
}

/// Spotify-like 1–2 tap add-to-playlist.
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
    shape: riffSheetShape,
    builder: (context) => AddToPlaylistSheet(songItems: songs),
  );
  if (Get.isRegistered<AddToPlaylistController>()) {
    Get.delete<AddToPlaylistController>();
  }
}

/// What happened when songs were written to a playlist.
enum PlaylistAddOutcome { added, alreadyIn, failed }

/// What to say when [songs] songs were written to a playlist (several:
/// a whole album or playlist, the queue).
String playlistAddMessageKey(PlaylistAddOutcome outcome, {int songs = 1}) {
  switch (outcome) {
    case PlaylistAddOutcome.added:
      return songs > 1
          ? 'songsAddedToPlaylistAlert'
          : 'songAddedToPlaylistAlert';
    case PlaylistAddOutcome.alreadyIn:
      return songs > 1 ? 'songsAlreadyInPlaylist' : 'songAlreadyExists';
    case PlaylistAddOutcome.failed:
      return 'operationFailed';
  }
}

/// Whether a playlist's stored songs ([entries], as its box keeps them)
/// include every one of [ids].
bool playlistHasAll(Iterable<dynamic> entries, Set<String> ids) {
  if (ids.isEmpty) return false;
  final have = {
    for (final e in entries)
      if (e is Map) '${e['videoId']}',
  };
  return have.containsAll(ids);
}

/// Of [added], the songs to download now that they're in a playlist whose
/// songs were [before] (its box's entries): when every song already in it
/// was downloaded, a downloaded playlist stays whole, as Spotify keeps
/// one, so the new ones not downloaded yet; else none.
List<MediaItem> songsToKeepDownloaded(
    Iterable<dynamic> before, Iterable<MediaItem> added,
    {required bool Function(String id) isDownloaded}) {
  final ids = [
    for (final e in before)
      if (e is Map) '${e['videoId']}',
  ];
  if (ids.isEmpty || !ids.every(isDownloaded)) return const [];
  return [
    for (final s in added)
      if (!isDownloaded(s.id)) s
  ];
}

/// Downloads [songs] for [songsToKeepDownloaded].
void keepPlaylistDownloaded(List<MediaItem> songs) {
  if (songs.isEmpty || !Get.isRegistered<Downloader>()) return;
  unawaited(Get.find<Downloader>().download(null, songList: songs));
}

/// Whether [id] is downloaded (in the SongDownloads box).
bool isSongDownloaded(String id) =>
    Hive.isBoxOpen('SongDownloads') &&
    Hive.box('SongDownloads').containsKey(id);

/// Writes to your playlist's [box] those of [songs] it hasn't got, each
/// once (a song twice among them goes in once), in their order; the ones
/// it took.
Future<List<MediaItem>> addNewSongsToPlaylistBox(
    Box box, List<MediaItem> songs) async {
  final have = {
    for (final e in box.values)
      if (e is Map) '${e['videoId']}',
  };
  final added = <MediaItem>[];
  for (final song in songs) {
    if (!have.add(song.id)) continue;
    await box.add(MediaItemBuilder.toJson(song));
    added.add(song);
  }
  return added;
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
    unawaited(SpotifyLikeSync.onFavorite(song, add: true));
    unawaited(YtLikeSync.onFavorite(song, add: true));
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

  /// Your playlists that already have every song being added, and whether
  /// your Favorites do: marked with a check, as Spotify and YouTube show
  /// where a song is saved.
  Set<String> _savedIn = const {};
  bool _inFavorites = false;

  @override
  void initState() {
    super.initState();
    final ids = {for (final s in widget.songItems) s.id};
    _inFavorites = Hive.isBoxOpen('LIBFAV') &&
        ids.every((id) => Hive.box('LIBFAV').containsKey(id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _findSavedIn(ids));
  }

  /// Looks through your own playlists (not YouTube or Piped ones) after
  /// the sheet is up; the checks show once that's done.
  Future<void> _findSavedIn(Set<String> ids) async {
    final found = <String>{};
    for (final p
        in userPlaylistsForAddSheet(fromLibrary: widget.playlistsOverride)) {
      if (p.isCloudPlaylist || p.isPipedPlaylist) continue;
      try {
        final box = Hive.isBoxOpen(p.playlistId)
            ? Hive.box(p.playlistId)
            : await Hive.openBox(p.playlistId);
        if (playlistHasAll(box.values, ids)) found.add(p.playlistId);
      } catch (_) {}
    }
    if (mounted && found.isNotEmpty) setState(() => _savedIn = found);
  }

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

  Future<void> _finish(PlaylistAddOutcome outcome) async {
    if (!mounted) return;
    Navigator.of(context).pop();
    _snack(playlistAddMessageKey(outcome, songs: widget.songItems.length).tr);
    if (outcome == PlaylistAddOutcome.added &&
        Get.isRegistered<DiscoveryService>()) {
      for (final song in widget.songItems) {
        Get.find<DiscoveryService>().onPlaylistAdd(song);
      }
    }
  }

  Future<void> _addToLiked() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    final added = await addSongsToLikedSongs(widget.songItems);
    await _finish(
      added ? PlaylistAddOutcome.added : PlaylistAddOutcome.alreadyIn,
    );
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    final controller = _controller();
    controller.playlistType.value =
        playlist.isPipedPlaylist ? 'piped' : 'local';
    final outcome = await controller.addSongsToPlaylist(
      widget.songItems,
      playlist.playlistId,
      context,
    );
    await _finish(outcome);
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
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context, liftAboveMiniPlayer: false),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RiffSheetHandle(),
          RiffSheetTitle(
            'addToPlaylist'.tr,
            subtitle: widget.songItems.length == 1
                ? widget.songItems.first.title
                : '${widget.songItems.length} ${'songs'.tr}',
          ),
          _SheetRow(
            leading: _SheetIcon(
              icon: Icons.favorite,
              color: theme.colorScheme.onSurface,
            ),
            title: 'favorites'.tr,
            saved: _inFavorites,
            onTap: _addToLiked,
          ),
          _SheetRow(
            leading: _SheetIcon(
              icon: Icons.add,
              color: theme.colorScheme.onSurface,
            ),
            title: 'CreateNewPlaylist'.tr,
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
    if (Get.isRegistered<AddToPlaylistController>()) {
      return Obx(
        () => _playlistTiles(
          Get.find<AddToPlaylistController>().playlists.toList(),
          muted,
        ),
      );
    }
    return _playlistTiles(const [], muted);
  }

  Widget _playlistTiles(List<Playlist> playlists, Color? muted) {
    if (playlists.isEmpty) {
      // No Align here: inside the height-capped box it would stretch to
      // the cap and leave a large empty gap under the message.
      return Padding(
        padding: const EdgeInsets.only(
            left: RiffSpacing.lg,
            top: RiffSpacing.sm,
            right: RiffSpacing.lg,
            bottom: RiffSpacing.lg),
        child: Text(
          'noPlaylistsYet'.tr,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: muted,
              ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: RiffSpacing.md),
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
          saved: _savedIn.contains(playlist.playlistId),
          onTap: () => _addToPlaylist(playlist),
        );
      },
    );
  }
}

/// Sheet row (§5.10): at least 52 tall, 16dp sides (ListTile theme), a
/// bodyLarge label in the primary text colour.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.leading,
    required this.title,
    required this.onTap,
    this.saved = false,
  });

  final Widget leading;
  final String title;
  final VoidCallback onTap;

  /// Already holds the songs: a check in the accent (toggled on, §2.5).
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      minTileHeight: RiffComponentSizes.sheetRow,
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge
            ?.copyWith(color: theme.colorScheme.onSurface),
      ),
      trailing: saved
          ? Icon(Icons.check_circle_rounded,
              size: RiffComponentSizes.trailingIcon,
              color: theme.colorScheme.primary,
              semanticLabel: 'alreadyInPlaylist'.tr)
          : null,
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
    // Flat surface2 tile on the sheet's surface1, radius 8.
    return Container(
      width: RiffComponentSizes.iconHit,
      height: RiffComponentSizes.iconHit,
      decoration: BoxDecoration(
        color: RiffColors.of(context).surface2,
        borderRadius: BorderRadius.circular(RiffRadii.sm),
      ),
      child: Icon(icon, color: color, size: RiffComponentSizes.sheetIcon),
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

  Future<PlaylistAddOutcome> addSongsToPlaylist(
      List<MediaItem> songs, String playlistId, BuildContext context) async {
    additionInProgress.value = true;
    if (playlistType.value == "local") {
      final plstBox = await Hive.openBox(playlistId);
      final before = plstBox.values.toList();
      final added = await addNewSongsToPlaylistBox(plstBox, songs);
      keepPlaylistDownloaded(
          songsToKeepDownloaded(before, added, isDownloaded: isSongDownloaded));
      // Shared box (Hive hands every caller the same instance): never close
      // it here, or the player and other screens using it fail mid-write.
      additionInProgress.value = false;
      return added.isNotEmpty
          ? PlaylistAddOutcome.added
          : PlaylistAddOutcome.alreadyIn;
    } else {
      final videosId = songs.map((e) => e.id).toList();
      try {
        final res =
            await Get.find<PipedServices>().addToPlaylist(playlistId, videosId);
        additionInProgress.value = false;
        return (res.code == 1)
            ? PlaylistAddOutcome.added
            : PlaylistAddOutcome.failed;
      } catch (_) {
        additionInProgress.value = false;
        return PlaylistAddOutcome.failed;
      }
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
