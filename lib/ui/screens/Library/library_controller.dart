import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

import '../../../utils/hive_boxes.dart';
import '../../../utils/house_keeping.dart';
import '../../widgets/add_to_playlist.dart';
import '/ui/widgets/sort_widget.dart';
import '/ui/theme/riff_spacing.dart';
import '../Settings/settings_screen_controller.dart';
import '/services/piped_service.dart';
import '/services/cloud_music_service.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/models/thumbnail.dart';

class LibrarySongsController extends GetxController {
  late RxList<MediaItem> librarySongsList = RxList();
  final isSongFetched = false.obs;
  /// When true, Songs shows cloud-server tracks instead of local downloads.
  final showCloudSongs = false.obs;
  List<MediaItem> tempListContainer = [];
  SortWidgetController? sortWidgetController;
  final additionalOperationMode = OperationMode.none.obs;

  Future<void> toggleCloudSongs() async {
    showCloudSongs.value = !showCloudSongs.value;
    if (!showCloudSongs.value) return;
    final cloud = Get.find<CloudMusicService>();
    if (cloud.isConnected.isFalse) return;
    if (cloud.songs.isEmpty) {
      try {
        await cloud.fetchRandomSongs();
      } catch (_) {/* status shown by service */}
    }
  }

  @override
  void onInit() {
    init();
    super.onInit();
  }

  Future<void> init() async {
    // Make sure that song cached in system or not cleared by system
    // if cleared then it will remove from database as well
    final cachedIds = <String>{};
    var listedOk = true;
    final cacheDir = (await getTemporaryDirectory()).path;
    final cachedSongsDir = Directory("$cacheDir/cachedSongs");
    try {
      // Async listing: listSync() on thousands of files stalls the UI isolate.
      if (await cachedSongsDir.exists()) {
        final idPattern = RegExp(".cachedSongs/([^#]*)?.mp3");
        await for (final f in cachedSongsDir.list()) {
          final ext = f.path.replaceAll(RegExp(r'^.*\.'), '');
          if (ext == 'mime' || ext == 'part') continue;
          final id = idPattern.firstMatch(f.path)?[1];
          if (id != null) cachedIds.add(id);
        }
      }
    } catch (e) {
      listedOk = false;
      printERROR("Cached songs listing failed: $e");
    }

    final box = Hive.box("SongsCache");
    final staleKeys =
        box.keys.where((key) => !cachedIds.contains(key)).toList();
    // A failed listing must not wipe the whole cache index.
    if (listedOk && staleKeys.isNotEmpty) await box.deleteAll(staleKeys);

    librarySongsList.value = box.values
        .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
        .whereType<MediaItem>()
        .toList();

    librarySongsList.addAll(Hive.box("SongDownloads")
        .values
        .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
        .whereType<MediaItem>()
        .toList());
    isSongFetched.value = true;

    //Remove deleted songs and expired songUrl from database
    startHouseKeeping();
  }

  void onSort(SortType sortType, bool isAscending) {
    final songlist = librarySongsList.toList();
    sortSongsNVideos(songlist, sortType, isAscending);
    librarySongsList.value = songlist;
  }

  void onSearchStart(String? tag) {
    tempListContainer = librarySongsList.toList();
  }

  void onSearch(String value, String? tag) {
    final songlist = tempListContainer
        .where((element) =>
            element.title.toLowerCase().contains(value.toLowerCase()))
        .toList();
    librarySongsList.value = songlist;
  }

  void onSearchClose(String? tag) {
    librarySongsList.value = tempListContainer.toList();
    tempListContainer.clear();
  }

  /// remove song from library list and from storage only, not from database
  Future<bool> removeSong(MediaItem item, bool isDownloaded,
      {String? url}) async {
    try {
      if (tempListContainer.isNotEmpty) {
        tempListContainer.remove(item);
      }
      librarySongsList.remove(item);
      String filePath = "";
      if (isDownloaded) {
        filePath = '${item.extras?['url'] ?? url ?? ''}';
      } else {
        final cacheDir = (await getTemporaryDirectory()).path;
        filePath = "$cacheDir/cachedSongs/${item.id}.mp3";
      }

      if (filePath.isNotEmpty && await (File(filePath)).exists()) {
        await (File(filePath)).delete();
      }

      final thumbFile = File(
          "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${item.id}.png");
      if (await thumbFile.exists()) {
        await thumbFile.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

//Additional operations
  final additionalOperationTempList = [].obs;
  final additionalOperationTempMap = <int, bool>{}.obs;

  void startAdditionalOperation(
      SortWidgetController sortWidgetController_, OperationMode mode) {
    sortWidgetController = sortWidgetController_;
    additionalOperationTempList.value = librarySongsList.toList();
    if (mode == OperationMode.addToPlaylist || mode == OperationMode.delete) {
      for (int i = 0; i < additionalOperationTempList.length; i++) {
        additionalOperationTempMap[i] = false;
      }
    }
    additionalOperationMode.value = mode;
  }

  void checkIfAllSelected() {
    sortWidgetController!.isAllSelected.value =
        !additionalOperationTempMap.containsValue(false);
  }

  void selectAll(bool selected) {
    for (int i = 0; i < additionalOperationTempList.length; i++) {
      additionalOperationTempMap[i] = selected;
    }
  }

  void performAdditionalOperation() {
    final currMode = additionalOperationMode.value;
    if (currMode == OperationMode.delete) {
      deleteMultipleSongs(selectedSongs()).then((value) {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    } else if (currMode == OperationMode.addToPlaylist) {
      final ctx = Get.context;
      if (ctx == null) return;
      showAddToPlaylistSheet(ctx, selectedSongs()).whenComplete(() {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    }
  }

  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {
    final downloadsBox = await Hive.openBox("SongDownloads");
    final cacheBox = await Hive.openBox("SongsCache");
    for (MediaItem element in songs) {
      if (downloadsBox.containsKey(element.id)) {
        await downloadsBox.delete(element.id);
        await removeSong(element, true);
      } else {
        await cacheBox.delete(element.id);
        await removeSong(element, false);
      }
    }
  }

  List<MediaItem> selectedSongs() {
    return additionalOperationTempMap.entries
        .map((item) {
          if (item.value) {
            return additionalOperationTempList[item.key];
          }
        })
        .whereType<MediaItem>()
        .toList();
  }

  void cancelAdditionalOperation() {
    sortWidgetController!.isAllSelected.value = false;
    sortWidgetController = null;
    additionalOperationMode.value = OperationMode.none;
    additionalOperationTempList.clear();
    additionalOperationTempMap.clear();
  }
}

class LibraryPlaylistsController extends GetxController
    with GetTickerProviderStateMixin {
  late AnimationController controller;

  final playlistCreationMode = "local".obs;
  static final initPlst = [
    Playlist(
        title: "recentlyPlayed".tr,
        playlistId: "LIBRP",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false),
    Playlist(
        title: "favorites".tr,
        playlistId: "LIBFAV",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false),
    Playlist(
        title: "cachedOrOffline".tr,
        playlistId: "SongsCache",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false),
    Playlist(
        title: "downloads".tr,
        playlistId: "SongDownloads",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false)
  ];
  late RxList<Playlist> libraryPlaylists = RxList(initPlst);
  final isContentFetched = false.obs;
  final creationInProgress = false.obs;
  final textInputController = TextEditingController();
  List<Playlist> tempListContainer = [];

  // Add these RxBool to track import progress
  final isImporting = false.obs;
  final importProgress = 0.0.obs;

  @override
  void onInit() {
    controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 5));
    refreshLib();
    super.onInit();
  }

  void refreshLib() async {
    // Shared box, kept open: closing it here raced other openers (playlist
    // screen, add-to-playlist) and forced a file re-read on every refresh.
    final box = await HiveBoxes.open("LibraryPlaylists");
    // Keep already-synced Piped playlists visible until the background sync
    // below reconciles them, so a refresh doesn't make them blink out.
    final piped = Hive.box("AppPrefs").get("piped");
    final pipedLoggedIn = piped is Map && piped['isLoggedIn'] == true;
    final pipedShown = pipedLoggedIn
        ? libraryPlaylists.where((p) => p.isPipedPlaylist).toList()
        : const <Playlist>[];
    libraryPlaylists.value = [
      ...initPlst,
      ...(box.values
          .map<Playlist?>((item) => Playlist.fromJson(item))
          .whereType<Playlist>()
          .toList()),
      ...pipedShown,
    ];
    // Local content is ready: don't hold the spinner on the network sync.
    isContentFetched.value = true;

    if (pipedLoggedIn) {
      try {
        await syncPipedPlaylist();
      } catch (e) {
        printERROR("Piped playlist sync failed: $e");
      }
    }
  }

  void updatePlaylistIntoDb(Playlist playlist) async {
    final box = await HiveBoxes.open("LibraryPlaylists");
    await box.put(playlist.playlistId, playlist.toJson());
    refreshLib();
  }

  void removePipedPlaylists() {
    for (Playlist plst in libraryPlaylists.toList()) {
      if (plst.isPipedPlaylist) {
        libraryPlaylists.remove(plst);
      }
    }
  }

  Future<bool> syncPipedPlaylist() async {
    final res = await Get.find<PipedServices>().getAllPlaylists();
    final box = await Hive.openBox('blacklistedPlaylist');
    final blacklistedPlaylist = box.values.whereType<String>().toList();
    final libPipedPlaylistsId = libraryPlaylists
            .toList()
            .map((e) {
              if (e.isPipedPlaylist) {
                return e.playlistId;
              }
            })
            .whereType<String>()
            .toList() +
        blacklistedPlaylist;

    if (res.code == 1) {
      final cloudpipedPlaylistsId = res.response
          .map((e) {
            return e['id'];
          })
          .whereType<String>()
          .toList();
      //add new playlist from cloud
      for (dynamic playlist in res.response) {
        if (!libPipedPlaylistsId.contains(playlist['id'])) {
          final plst = Playlist(
            title: playlist['name'],
            playlistId: playlist['id'],
            description: "Piped Playlist",
            thumbnailUrl: playlist['thumbnail'],
            isPipedPlaylist: true,
          );
          libraryPlaylists.add(plst);
        }
      }

      //remove playist if removed from cloud
      for (Playlist playlist in libraryPlaylists.toList()) {
        if (!cloudpipedPlaylistsId.contains(playlist.playlistId) &&
            playlist.isPipedPlaylist) {
          libraryPlaylists.removeWhere(
              (element) => element.playlistId == playlist.playlistId);
        }
      }
    }
    return res.code == 1;
  }

  Future<bool> renamePlaylist(Playlist playlist) async {
    String title = textInputController.text;
    if (title.trim().isNotEmpty) {
      if (playlist.isPipedPlaylist) {
        final res = await Get.find<PipedServices>()
            .renamePlaylist(playlist.playlistId, title);
        if (res.code == 0) return false;
        playlist.newTitle = title;
      } else {
        final box = await HiveBoxes.open("LibraryPlaylists");
        title = "${title[0].toUpperCase()}${title.substring(1).toLowerCase()}";
        playlist.newTitle = title;
        await box.put(playlist.playlistId, playlist.toJson());
      }
      refreshLib();
      return true;
    }
    return false;
  }

  void changeCreationMode(String? val) {
    playlistCreationMode.value = val!;
  }

  Future<bool> createNewPlaylist(
      {bool createPlaylistNaddSong = false, List<MediaItem>? songItems}) async {
    String title = textInputController.text;
    if (title.trim().isNotEmpty) {
      dynamic newplst;

      if (playlistCreationMode.value == "piped") {
        creationInProgress.value = true;
        final res = await Get.find<PipedServices>().createPlaylist(title);
        if (res.code == 1) {
          newplst = Playlist(
              title: title,
              playlistId: "${res.response['playlistId']}",
              thumbnailUrl: songItems != null
                  ? songItems[0].artUri.toString()
                  : Playlist.thumbPlaceholderUrl,
              description: "Piped Playlist",
              isCloudPlaylist: true,
              isPipedPlaylist: true);
        } else {
          creationInProgress.value = false;
          return false;
        }
      } else {
        newplst = Playlist(
            title: title,
            playlistId: "LIB${DateTime.now().millisecondsSinceEpoch}",
            thumbnailUrl: songItems != null
                ? songItems[0].artUri.toString()
                : Playlist.thumbPlaceholderUrl,
            description: "Library Playlist",
            isCloudPlaylist: false);
        final box = await HiveBoxes.open("LibraryPlaylists");
        await box.put(newplst.playlistId, newplst.toJson());
      }

      libraryPlaylists.add(newplst);

      if (createPlaylistNaddSong && playlistCreationMode.value == "local") {
        final plastbox = await Hive.openBox(newplst.playlistId);
        await plastbox
            .addAll(songItems!.map((item) => MediaItemBuilder.toJson(item)));
        await plastbox.close();
      } else if ((createPlaylistNaddSong &&
          playlistCreationMode.value == "piped")) {
        final songIds = songItems!.map((e) => e.id).toList();
        final added = await Get.find<PipedServices>()
            .addToPlaylist(newplst.playlistId, songIds);
        if (added.code != 1) {
          creationInProgress.value = false;
          return false;
        }
      }
      creationInProgress.value = false;
      return true;
    }
    return false;
  }

  Future<bool> blacklistPipedPlaylist(Playlist playlist) async {
    try {
      final box = await Hive.openBox('blacklistedPlaylist');
      await box.add(playlist.playlistId);
      libraryPlaylists.remove(playlist);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetBlacklistedPlaylist() async {
    try {
      final box = await Hive.openBox('blacklistedPlaylist');
      await box.clear();
      return syncPipedPlaylist();
    } catch (_) {
      return false;
    }
  }

  void onSort(SortType sortType, bool isAscending) {
    final playlists = libraryPlaylists.toList();
    playlists.removeRange(0, 4);
    sortPlayLists(playlists, sortType, isAscending);
    playlists.insertAll(0, initPlst);
    libraryPlaylists.value = playlists;
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryPlaylists.toList();
  }

  void onSearch(String value, String? tag) {
    final songlist = tempListContainer
        .where((element) =>
            element.title.toLowerCase().contains(value.toLowerCase()))
        .toList();
    libraryPlaylists.value = songlist;
  }

  void onSearchClose(String? tag) {
    libraryPlaylists.value = tempListContainer.toList();
    tempListContainer.clear();
  }

  @override
  void onClose() {
    textInputController.dispose();
    controller.dispose();
    super.onClose();
  }

  Future<void> importPlaylistFromJson(BuildContext context) async {
    try {
      isImporting.value = true;
      importProgress.value = 0.1;

      // Show progress dialog
      if (context.mounted) {
        _showImportProgressDialog(context);
      }

      // Use file_picker to select JSON file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'importPlaylist'.tr,
      );

      if (result == null || result.files.isEmpty) {
        // User cancelled the picker
        if (Get.isDialogOpen ?? false) {
          Get.back();
        }
        isImporting.value = false;
        importProgress.value = 0.0;
        return;
      }

      importProgress.value = 0.2;

      final file = File(result.files.single.path!);
      if (!await file.exists()) {
        throw FileSystemException("fileNotFound".tr);
      }

      final jsonString = await file.readAsString();
      importProgress.value = 0.3;

      final jsonData = jsonDecode(jsonString);
      importProgress.value = 0.4;

      // Validate JSON structure
      if (!jsonData.containsKey('playlistInfo') ||
          !jsonData.containsKey('songs')) {
        throw FormatException("invalidPlaylistFile".tr);
      }

      // Create new playlist ID
      final playlistInfo = jsonData['playlistInfo'];
      final newPlaylistId = "LIB${DateTime.now().millisecondsSinceEpoch}";
      importProgress.value = 0.5;

      // Create playlist object
      final newPlaylist = Playlist(
        title: "${playlistInfo['title']} (${"imported".tr})",
        playlistId: newPlaylistId,
        thumbnailUrl: playlistInfo['thumbnailUrl'] ??
            (playlistInfo['thumbnails'] != null
                ? Thumbnail.bestUrl(playlistInfo['thumbnails'],
                    target: 'extraHigh',
                    fallback: Playlist.thumbPlaceholderUrl)
                : Playlist.thumbPlaceholderUrl),
        description: playlistInfo['description'] ?? "importedPlaylist".tr,
        isCloudPlaylist: false,
      );
      importProgress.value = 0.6;

      // Save playlist to database
      final box = await HiveBoxes.open("LibraryPlaylists");
      await box.put(newPlaylistId, newPlaylist.toJson());
      importProgress.value = 0.7;

      // Save songs to playlist in one batched write (was one flush per song).
      final songsBox = await Hive.openBox(newPlaylistId);
      final songsList = jsonData['songs'] as List;
      await songsBox.putAll({
        for (int i = 0; i < songsList.length; i++) i: songsList[i],
      });
      importProgress.value = 0.95;

      // Freshly created, uniquely named box that nothing else holds yet.
      await songsBox.close();
      importProgress.value = 1.0;

      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      // Refresh library to show the new playlist
      refreshLib();

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(
            context,
            "${"playlistImportedMsg".tr}: ${newPlaylist.title}",
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      printERROR("Error importing playlist: $e");

      String errorMsg = "importError".tr;
      if (e is FileSystemException) {
        errorMsg = "importErrorFileAccess".tr;
      } else if (e is FormatException) {
        errorMsg = "importErrorFormat".tr;
      } else if (e.toString().contains("invalidPlaylistFile")) {
        errorMsg = "invalidPlaylistFile".tr;
      } else if (e is HiveError) {
        errorMsg = "importErrorDatabase".tr;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      isImporting.value = false;
      importProgress.value = 0.0;
    }
  }

  // Helper method to show import progress dialog
  void _showImportProgressDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: Text("importingPlaylist".tr),
        content: Obx(() => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: Get.isRegistered<LibraryPlaylistsController>()
                      ? importProgress.value
                      : 0,
                ),
                const SizedBox(height: RiffSpacing.lg),
                Text(
                  "${(Get.isRegistered<LibraryPlaylistsController>() ? importProgress.value * 100 : 0).toInt()}%",
                ),
              ],
            )),
      ),
      barrierDismissible: false,
      barrierColor: Theme.of(context).dialogTheme.barrierColor,
    );
  }
}

class LibraryAlbumsController extends GetxController {
  late RxList<Album> libraryAlbums = RxList();
  final isContentFetched = false.obs;
  List<Album> tempListContainer = [];

  @override
  void onInit() {
    refreshLib();
    super.onInit();
  }

  void refreshLib() async {
    // Shared box, kept open (closing it broke concurrent openers).
    final box = await HiveBoxes.open("LibraryAlbums");
    libraryAlbums.value = box.values
        .map<Album?>((item) => Album.fromJson(item))
        .whereType<Album>()
        .toList();

    isContentFetched.value = true;
  }

  void onSort(SortType sortType, bool isAscending) {
    final albumList = libraryAlbums.toList();
    sortAlbumNSingles(albumList, sortType, isAscending);
    libraryAlbums.value = albumList;
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryAlbums.toList();
  }

  void onSearch(String value, String? tag) {
    final songlist = tempListContainer
        .where((element) =>
            element.title.toLowerCase().contains(value.toLowerCase()))
        .toList();
    libraryAlbums.value = songlist;
  }

  void onSearchClose(String? tag) {
    libraryAlbums.value = tempListContainer.toList();
    tempListContainer.clear();
  }
}

class LibraryArtistsController extends GetxController {
  RxList<Artist> libraryArtists = RxList();
  final isContentFetched = false.obs;
  List<Artist> tempListContainer = [];

  @override
  void onInit() {
    refreshLib();
    super.onInit();
  }

  void refreshLib() async {
    // Shared box, kept open (closing it broke concurrent openers).
    final box = await HiveBoxes.open("LibraryArtists");
    libraryArtists.value = box.values
        .map<Artist?>((item) => Artist.fromJson(item))
        .whereType<Artist>()
        .toList();
    isContentFetched.value = true;
  }

  void onSort(SortType sortType, bool isAscending) {
    final artistList = libraryArtists.toList();
    sortArtist(artistList, sortType, isAscending);
    libraryArtists.value = artistList;
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryArtists.toList();
  }

  void onSearch(String value, String? tag) {
    final songlist = tempListContainer
        .where((element) =>
            element.name.toLowerCase().contains(value.toLowerCase()))
        .toList();
    libraryArtists.value = songlist;
  }

  void onSearchClose(String? tag) {
    libraryArtists.value = tempListContainer.toList();
    tempListContainer.clear();
  }
}
