import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/thumbnail.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import '../../../base_class/playlist_album_screen_con_base.dart';
import '../../../mixins/additional_opeartion_mixin.dart';
import '../../../models/album.dart' show Album;
import '../../../models/media_Item_builder.dart';
import '../../../models/playlist.dart';
import '../../../services/music_service.dart';
import '../../../services/piped_service.dart';
import '../../../services/playlist_mix_service.dart';
import '../../../services/track_analysis_service.dart';
import '../Home/home_screen_controller.dart';
import '../Library/library_controller.dart';
import '../Podcasts/podcasts_library_controller.dart';

///PlaylistScreenController handles playlist screen
///
///Playlist title,image,songs
class PlaylistScreenController extends PlaylistAlbumScreenControllerBase
    with AdditionalOpeartionMixin, GetSingleTickerProviderStateMixin {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final playlist = Playlist(
    title: "",
    playlistId: "",
    thumbnailUrl: Playlist.thumbPlaceholderUrl,
  ).obs;
  final isDefaultPlaylist = false.obs;

  // True only when this playlist was opened from the podcast *search* screen.
  // Drives the pinned "Similar podcasts" section at the bottom (passed as the
  // optional 3rd navigation argument).
  final showSimilarPodcasts = false.obs;

  // Add this RxBool to track export progress
  final isExporting = false.obs;
  final exportProgress = 0.0.obs;

  /// Spotify-like Mix mode: BPM / Camelot + Auto transitions.
  final isMixMode = false.obs;
  final isAnalyzingMix = false.obs;
  final mixAnalyzeProgress = 0.0.obs;
  final mixAnalyses = <String, TrackAnalysis>{}.obs;
  /// Gap index → transition style name (reactive for UI chips).
  final mixTransitions = <int, MixTransitionStyle>{}.obs;

  String generatedYtmPlaylistUrl = '';

  // Title animation

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _heightAnimation;

  AnimationController get animationController => _animationController;
  Animation<double> get scaleAnimation => _scaleAnimation;
  Animation<double> get heightAnimation => _heightAnimation;
  @override
  void onInit() {
    super.onInit();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation =
        Tween<double>(begin: 0, end: 1.0).animate(animationController);

    // Tall enough for the cover thumbnail + title row (64px art).
    _heightAnimation =
        Tween<double>(begin: 10.0, end: 80.0).animate(CurvedAnimation(parent: animationController, curve: Curves.easeOutBack));

    final args = Get.arguments as List;
    final Playlist? playlist = args[0];
    final playlistId = args[1];
    // Optional 3rd arg: opened from podcast search -> show pinned similar row.
    showSimilarPodcasts.value = args.length > 2 && args[2] == true;
    fetchPlaylistDetails(playlist, playlistId);
    _restoreMixState(playlistId);
    Future.delayed(const Duration(milliseconds: 200),
        () => Get.find<HomeScreenController>().whenHomeScreenOnTop());
  }

  void _restoreMixState(String playlistId) {
    if (!Get.isRegistered<PlaylistMixService>()) return;
    final mix = Get.find<PlaylistMixService>();
    final enabled = mix.isMixEnabled(playlistId);
    isMixMode.value = enabled;
    if (enabled) {
      _loadTransitionMap();
      // Kick off analysis after songs load (non-blocking).
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!isClosed && isMixMode.isTrue) analyzePlaylistForMix();
      });
    }
  }

  void _loadTransitionMap() {
    if (!Get.isRegistered<PlaylistMixService>()) return;
    final mix = Get.find<PlaylistMixService>();
    final id = playlist.value.playlistId;
    final map = <int, MixTransitionStyle>{};
    for (var i = 0; i < songList.length - 1; i++) {
      map[i] = mix.transitionAt(id, i);
    }
    mixTransitions.assignAll(map);
  }

  MixTransitionStyle transitionForGap(int gapIndex) {
    return mixTransitions[gapIndex] ??
        (Get.isRegistered<PlaylistMixService>()
            ? Get.find<PlaylistMixService>()
                .transitionAt(playlist.value.playlistId, gapIndex)
            : MixTransitionStyle.auto);
  }

  Future<void> setTransitionForGap(
      int gapIndex, MixTransitionStyle style) async {
    mixTransitions[gapIndex] = style;
    mixTransitions.refresh();
    if (Get.isRegistered<PlaylistMixService>()) {
      await Get.find<PlaylistMixService>()
          .setTransitionAt(playlist.value.playlistId, gapIndex, style);
    }
  }

  Future<void> toggleMixMode() async {
    final pl = playlist.value;
    if (pl.kind == 'podcast' || pl.playlistId.startsWith('MPSP')) {
      return;
    }
    final next = !isMixMode.value;
    isMixMode.value = next;
    if (Get.isRegistered<PlaylistMixService>()) {
      await Get.find<PlaylistMixService>()
          .setMixEnabled(pl.playlistId, next);
    }
    if (next) {
      _loadTransitionMap();
      await analyzePlaylistForMix();
    }
  }

  Future<void> analyzePlaylistForMix() async {
    if (!Get.isRegistered<TrackAnalysisService>()) return;
    if (songList.isEmpty || isAnalyzingMix.isTrue) return;
    isAnalyzingMix.value = true;
    mixAnalyzeProgress.value = 0;
    try {
      final svc = Get.find<TrackAnalysisService>();
      // Seed from cache first for snappy UI.
      for (final s in songList) {
        final cached = svc.cached(s.title, s.artist ?? '');
        if (cached != null) mixAnalyses[s.id] = cached;
      }
      mixAnalyses.refresh();

      final tracks = songList
          .map((s) => (
                id: s.id,
                title: s.title,
                artist: s.artist ?? '',
              ))
          .toList();
      final result = await svc.analyzeMany(tracks, onProgress: (done, total) {
        if (total > 0) mixAnalyzeProgress.value = done / total;
      });
      mixAnalyses.addAll(result);
      mixAnalyses.refresh();
      _loadTransitionMap();
    } finally {
      isAnalyzingMix.value = false;
    }
  }

  /// Reorder tracks for smoother Mix flow (BPM + Camelot greedy path).
  Future<void> smartOrderForMix() async {
    if (songList.length < 2) return;
    final analyses = Map<String, TrackAnalysis>.from(mixAnalyses);
    final remaining = songList.toList();
    final ordered = <MediaItem>[];

    // Start with a mid-tempo track when possible.
    remaining.sort((a, b) {
      final ba = analyses[a.id]?.bpm ?? 120;
      final bb = analyses[b.id]?.bpm ?? 120;
      return (ba - 120).abs().compareTo((bb - 120).abs());
    });
    ordered.add(remaining.removeAt(0));

    while (remaining.isNotEmpty) {
      final prev = ordered.last;
      final prevA = analyses[prev.id];
      var bestIdx = 0;
      var bestScore = 1 << 30;
      for (var i = 0; i < remaining.length; i++) {
        final cand = remaining[i];
        final ca = analyses[cand.id];
        var score = 50;
        if (prevA != null && ca != null) {
          final keyDist =
              TrackAnalysisService.camelotDistance(prevA.camelot, ca.camelot);
          final bpmDist = (prevA.bpm - ca.bpm).abs();
          score = keyDist * 10 + (bpmDist / 2).round();
        } else if (prevA != null || ca != null) {
          score = 80;
        }
        if (score < bestScore) {
          bestScore = score;
          bestIdx = i;
        }
      }
      ordered.add(remaining.removeAt(bestIdx));
    }

    songList.value = ordered;
    if (!playlist.value.isCloudPlaylist &&
        playlist.value.playlistId != 'LIBRP' &&
        playlist.value.playlistId != 'SongDownloads' &&
        playlist.value.playlistId != 'SongsCache') {
      await updateSongsIntoDb();
    }
    _loadTransitionMap();
  }

  ///Fetches playlist details from the service
  @override
  void fetchPlaylistDetails(Playlist? playlist_, String playlistId) async {
    final isIdOnly = playlist_ == null;
    final isPipedPlaylist = playlist_?.isPipedPlaylist ?? false;
    isDefaultPlaylist.value = (playlistId == "SongDownloads" ||
        playlistId == "SongsCache" ||
        playlistId == "LIBRP" ||
        playlistId == "LIBFAV");

    if (!isIdOnly && !playlist_.isCloudPlaylist) {
      playlist.value = playlist_;
      _animationController.forward();
      fetchSongsfromDatabase(playlistId);
      isContentFetched.value = true;

      Future.delayed(
          const Duration(seconds: 1), () => _updatePlaylistThumbSongBased());

      return;
    }

    if (!isIdOnly) {
      playlist.value = playlist_;
      _animationController.forward();
    }

    try {
      // Check if the playlist is offline
      if (await checkIfAddedToLibrary(playlistId)) {
        final songsBox = await Hive.openBox(playlistId);
        if (songsBox.values.isEmpty) {
          _fetchSongOnline(playlistId, isIdOnly, isPipedPlaylist).then((value) {
            updateSongsIntoDb();
          });
        } else {
          // If the playlist is offline, fetch the songs from the local database
          // Playlist details are already fetched in _checkIfAddedToLibrary method
          fetchSongsfromDatabase(playlistId);
        }
      } else {
        _fetchSongOnline(playlistId, isIdOnly, isPipedPlaylist);
      }
      isContentFetched.value = true;
    } catch (e) {
      // Handle any errors that occur during the fetch
      printERROR("Error fetching playlist details: $e");
    }
  }

  Future<void> _fetchSongOnline(
      String id, bool isIdOnly, bool isPipedPlaylist) async {
    isContentFetched.value = false;

    if (isPipedPlaylist) {
      songList.value = (await Get.find<PipedServices>().getPlaylistSongs(id));
      isContentFetched.value = true;
      checkDownloadStatus();
      return;
    }

    final content =
        await _musicServices.getPlaylistOrAlbumSongs(playlistId: id);

    if (isIdOnly) {
      content['playlistId'] = id;
      playlist.value = Playlist.fromJson(content);
      _animationController.forward();
    } else if (content['kind'] == 'podcast' || id.startsWith('MPSP')) {
      // Keep episode list metadata in sync for podcasts
      final thumbs = content['thumbnails'];
      final newThumb = Thumbnail.bestUrl(
        thumbs,
        target: 'extraHigh',
        preferSquare: true,
      );
      playlist.value = playlist.value.copyWith(
        title: content['title']?.toString() ?? playlist.value.title,
        thumbnailUrl: newThumb.isNotEmpty ? newThumb : null,
        kind: 'podcast',
      );
    }
    songList.value = List<MediaItem>.from(content['tracks'] ?? const []);
    checkDownloadStatus();
  }

  @override
  void syncPlaylistSongs() {
    _fetchSongOnline(playlist.value.playlistId, false, false).then((value) {
      updateSongsIntoDb();
      isContentFetched.value = true;
    });
  }

  bool _isPodcastContent(dynamic content) {
    if (content is Playlist) {
      return content.kind == 'podcast' ||
          content.playlistId.startsWith('MPSP') ||
          (content.description?.toLowerCase().contains('podcast') ?? false);
    }
    return false;
  }

  @override
  Future<bool> checkIfAddedToLibrary(String id) async {
    if (id.startsWith('MPSP') || playlist.value.kind == 'podcast') {
      final box = await Hive.openBox('LibraryPodcasts');
      isAddedToLibrary.value = box.containsKey(id);
      if (isAddedToLibrary.value) {
        playlist.value = Playlist.fromJson(box.get(id));
      }
      return isAddedToLibrary.value;
    }
    final box = await Hive.openBox("LibraryPlaylists");
    isAddedToLibrary.value = box.containsKey(id);
    if (isAddedToLibrary.value) playlist.value = Playlist.fromJson(box.get(id));
    await box.close();
    return isAddedToLibrary.value;
  }

  @override
  Future<bool> addNremoveFromLibrary(dynamic content, {bool add = true}) async {
    try {
      if (_isPodcastContent(content)) {
        final box = await Hive.openBox('LibraryPodcasts');
        final id = content.playlistId as String;
        if (add) {
          final json = content is Playlist
              ? {...content.toJson(), 'kind': 'podcast'}
              : content.toJson();
          await box.put(id, json);
        } else {
          await box.delete(id);
        }
        isAddedToLibrary.value = add;
        if (Get.isRegistered<LibraryPodcastsController>()) {
          await Get.find<LibraryPodcastsController>().refreshLib();
        }
        return true;
      }
      if (content.isPipedPlaylist && !add) {
        //remove piped playlist from lib
        final res =
            await Get.find<PipedServices>().deletePlaylist(content.playlistId);
        Get.find<LibraryPlaylistsController>().syncPipedPlaylist();
        return (res.code == 1);
      } else {
        final box = await Hive.openBox("LibraryPlaylists");
        final id = content.playlistId;
        if (add) {
          box.put(id, content.toJson());
          updateSongsIntoDb();
        } else {
          box.delete(id);
          final songsBox = await Hive.openBox(id);
          songsBox.deleteFromDisk();
        }
        isAddedToLibrary.value = add;
      }
      //Update frontend
      Get.find<LibraryPlaylistsController>().refreshLib();
      if (!content.isCloudPlaylist && !add) {
        final plstbox = await Hive.openBox(content.playlistId);
        plstbox.deleteFromDisk();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateSongsIntoDb() async {
    final songsBox = await Hive.openBox(playlist.value.playlistId);
    await songsBox.clear();
    final songListCopy = songList.toList();
    for (int i = 0; i < songListCopy.length; i++) {
      await songsBox.put(i, MediaItemBuilder.toJson(songListCopy[i]));
    }
    if (playlist.value.playlistId != "SongDownloads") await songsBox.close();

    // Update the playlist thumbnail based on the first song's thumbnail
    _updatePlaylistThumbSongBased();
  }

  @override
  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {
    final id = playlist.value.playlistId;
    final isoffline = id == "SongsCache" || id == "SongDownloads";

    final box_ = await Hive.openBox(id);
    for (MediaItem element in songs) {
      final index = box_.values
          .toList()
          .indexWhere((ele) => ele['videoId'] == element.id);
      await box_.deleteAt(index);

      if (isoffline) {
        await Get.find<LibrarySongsController>()
            .removeSong(element, id == "SongDownloads");
      }

      songList.removeWhere((song) => song.id == element.id);
    }
    if (!isoffline) await box_.close();

    // Update the playlist thumbnail based on the first song's thumbnail
    _updatePlaylistThumbSongBased();
  }

  void addNRemoveItemsinList(MediaItem? item,
      {required String action, int? index}) {
    if (action == 'add') {
      if (tempListContainer.isNotEmpty) {
        index != null
            ? tempListContainer.insert(index, item!)
            : tempListContainer.add(item!);
        return;
      }
      index != null ? songList.insert(index, item!) : songList.add(item!);
    } else {
      if (tempListContainer.isNotEmpty) {
        index != null
            ? tempListContainer.removeAt(index)
            : tempListContainer.remove(item);
      }
      index != null ? songList.removeAt(index) : songList.remove(item);
    }

    // update the playlist thumbnail based on the first song's thumbnail
    _updatePlaylistThumbSongBased();
  }

  @override
  void fetchAlbumDetails(Album? album_,String albumId) {} // Not used in this class

  /// This function updates the local playlist thumbnail based on the first song's thumbnail
  void _updatePlaylistThumbSongBased() {
    final currentPlaylist = playlist.value;

    if (isDefaultPlaylist.isTrue || currentPlaylist.isCloudPlaylist) {
      return;
    }

    Playlist updatedplaylist;
    if (songList.isNotEmpty) {
      updatedplaylist =
          currentPlaylist.copyWith(thumbnailUrl: songList[0].artUri.toString());
    } else {
      updatedplaylist =
          currentPlaylist.copyWith(thumbnailUrl: Playlist.thumbPlaceholderUrl);
    }

    // Check if the thumbnail URL is the same as the current one
    // If it is, no need to update the playlist
    if (Thumbnail(currentPlaylist.thumbnailUrl).extraHigh ==
        Thumbnail(updatedplaylist.thumbnailUrl).extraHigh) {
      return;
    }

    // Update the playlist thumbnail URL
    playlist.value = updatedplaylist;
    Get.find<LibraryPlaylistsController>()
        .updatePlaylistIntoDb(updatedplaylist);
  }

  @override
  void onClose() {
    tempListContainer.clear();
    _animationController.dispose();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onClose();
  }

  Future<void> exportPlaylistToJson(BuildContext context) async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "permissionDenied".tr,
            size: SanckBarSize.MEDIUM));
      }
      return;
    }

    try {
      isExporting.value = true;
      exportProgress.value = 0.1;

      // Show progress dialog
      if (context.mounted) {
        _showProgressDialog(context, "exportingPlaylist".tr);
      }

      // Get appropriate directory based on platform
      final Directory exportDir = await _getExportDirectory();
      exportProgress.value = 0.2;

      // Create playlist data map
      final playlistData = {
        "playlistInfo": playlist.value.toJson(),
        "songs": songList.map((song) => MediaItemBuilder.toJson(song)).toList(),
        "exportDate": DateTime.now().toIso8601String(),
        "appVersion": Get.find<SettingsScreenController>().currentVersion,
      };
      exportProgress.value = 0.5;

      // Generate filename with playlist name
      final sanitizedName =
          playlist.value.title.replaceAll(RegExp(r'[^\w\s]+'), '_');

      // Find available filename with incremental suffix if needed
      String filename = "$sanitizedName.json";
      String filePath = "${exportDir.path}/$filename";
      File file = File(filePath);

      int counter = 1;
      while (await file.exists()) {
        filename = "${sanitizedName}_$counter.json";
        filePath = "${exportDir.path}/$filename";
        file = File(filePath);
        counter++;
      }

      exportProgress.value = 0.7;

      // Write JSON to file
      await file.writeAsString(jsonEncode(playlistData));
      exportProgress.value = 1.0;

      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      // Show success message with platform-specific path info
      String locationMsg = _getLocationMessage(exportDir.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "${"playlistExportedMsg".tr}: $locationMsg",
            size: SanckBarSize.MEDIUM));
      }
    } catch (e) {
      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      printERROR("Error exporting playlist: $e");
      
      String errorMsg = "exportError".tr;
      if (e is FileSystemException) {
        if (e.osError?.errorCode == 13) {
          errorMsg = "exportErrorPermission".tr;
        } else if (e.osError?.errorCode == 28) {
          errorMsg = "exportErrorStorage".tr;
        }
      } else if (e is FormatException) {
        errorMsg = "exportErrorFormat".tr;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      isExporting.value = false;
      exportProgress.value = 0.0;
    }
  }

  Future<void> exportPlaylistToCsv(BuildContext context) async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "permissionDenied".tr,
            size: SanckBarSize.MEDIUM));
      }
      return;
    }

    try {
      isExporting.value = true;
      exportProgress.value = 0.1;

      // Show progress dialog
      if (context.mounted) {
        _showProgressDialog(context, "exportingPlaylist".tr);
      }

      // Get appropriate directory based on platform
      final Directory exportDir = await _getExportDirectory();
      exportProgress.value = 0.2;

      // Build CSV content
      final csvContent = _generateCsvContent();
      exportProgress.value = 0.5;

      // Generate filename with playlist name
      final sanitizedName =
          playlist.value.title.replaceAll(RegExp(r'[^\w\s]+'), '_');

      // Find available filename with incremental suffix if needed
      String filename = "$sanitizedName.csv";
      String filePath = "${exportDir.path}/$filename";
      File file = File(filePath);

      int counter = 1;
      while (await file.exists()) {
        filename = "${sanitizedName}_$counter.csv";
        filePath = "${exportDir.path}/$filename";
        file = File(filePath);
        counter++;
      }

      exportProgress.value = 0.7;

      // Write CSV to file
      await file.writeAsString(csvContent);
      exportProgress.value = 1.0;

      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      // Show success message with platform-specific path info
      String locationMsg = _getLocationMessage(exportDir.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "${"playlistExportedMsg".tr}: $locationMsg",
            size: SanckBarSize.MEDIUM));
      }
    } catch (e) {
      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      printERROR("Error exporting playlist to CSV: $e");
      
      String errorMsg = "exportError".tr;
      if (e is FileSystemException) {
        if (e.osError?.errorCode == 13) {
          errorMsg = "exportErrorPermission".tr;
        } else if (e.osError?.errorCode == 28) {
          errorMsg = "exportErrorStorage".tr;
        }
      } else if (e is FormatException) {
        errorMsg = "exportErrorFormat".tr;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      isExporting.value = false;
      exportProgress.value = 0.0;
    }
  }

  String _generateCsvContent() {
    final buffer = StringBuffer();
    
    // CSV Header
    buffer.writeln('PlaylistBrowseId,PlaylistName,MediaId,Title,Artists,Duration,ThumbnailUrl,AlbumId,AlbumTitle,ArtistIds');
    
    // CSV Rows - one for each song
    for (final song in songList) {
      // Keep playlistBrowseId blank for offline/piped playlists
      final playlistBrowseId = (!playlist.value.isCloudPlaylist || playlist.value.isPipedPlaylist)
          ? ''
          : _escapeCsvField(playlist.value.playlistId);
      final playlistName = _escapeCsvField(playlist.value.title);
      final mediaId = _escapeCsvField(song.id);
      final title = _escapeCsvField(song.title);
      
      // Extract artists as comma-separated string
      final artistsList = song.extras?['artists'] as List?;
      final artists = artistsList != null
          ? _escapeCsvField(artistsList.map((a) => a['name']).join(', '))
          : '';
      
      // Format duration as HH:MM:SS or MM:SS
      final duration = song.duration != null
          ? _formatDuration(song.duration!)
          : '';
      
      final thumbnailUrl = _escapeCsvField(song.artUri.toString());
      
      // Extract album information
      final albumData = song.extras?['album'] as Map?;
      final albumId = albumData != null ? _escapeCsvField(albumData['id'] ?? '') : '';
      final albumTitle = albumData != null ? _escapeCsvField(albumData['name'] ?? '') : '';
      
      // Extract all artist IDs (comma-separated)
      final artistIds = artistsList != null && artistsList.isNotEmpty
          ? _escapeCsvField(artistsList.map((a) => a['id'] ?? '').join(','))
          : '';
      
      buffer.writeln('$playlistBrowseId,$playlistName,$mediaId,$title,$artists,$duration,$thumbnailUrl,$albumId,$albumTitle,$artistIds');
    }
    
    return buffer.toString();
  }

  String _escapeCsvField(String field) {
    // Escape double quotes by doubling them
    String escaped = field.replaceAll('"', '""');
    
    // If field contains comma, newline, or double quote, wrap in quotes
    if (escaped.contains(',') || escaped.contains('\n') || escaped.contains('"')) {
      escaped = '"$escaped"';
    }
    
    return escaped;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  // Helper method to get the appropriate export directory for each platform
  Future<Directory> _getExportDirectory() async {
    Directory directory;
    const appFolderName = "HarmonyMusic";

    try {
      if (Platform.isAndroid) {
        // Android: use Downloads folder
        directory = Directory('/storage/emulated/0/Download/$appFolderName');
      } else if (Platform.isIOS) {
        // iOS: use Documents directory
        final docDir = await path_provider.getApplicationDocumentsDirectory();
        directory = Directory('${docDir.path}/$appFolderName');
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop platforms: use Downloads folder in user's home directory
        final homeDir = Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
        directory = Directory('$homeDir/Downloads/$appFolderName');
      } else {
        // Fallback: use temporary directory
        final tempDir = await path_provider.getTemporaryDirectory();
        directory = Directory('${tempDir.path}/$appFolderName');
      }

      // Create directory if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      return directory;
    } catch (e) {
      // Fallback to app's documents directory if any error occurs
      final appDocDir = await path_provider.getApplicationDocumentsDirectory();
      directory = Directory('${appDocDir.path}/$appFolderName');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }
  }

  // Helper method to get a user-friendly location message
  String _getLocationMessage(String path) {
    if (Platform.isAndroid) {
      return "Downloads/HarmonyMusic";
    } else if (Platform.isIOS) {
      return "Files App > HarmonyMusic";
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return "Downloads/HarmonyMusic";
    } else {
      return path.split('/').last;
    }
  }

  // Helper method to show progress dialog
  void _showProgressDialog(BuildContext context, String title) {
    Get.dialog(
      AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Obx(() => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: exportProgress.value,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "${(exportProgress.value * 100).toInt()}%",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            )),
      ),
      barrierDismissible: false,
    );
  }
}
