import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:audiotags/audiotags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../ui/screens/Album/album_screen_controller.dart';
import '../ui/screens/Playlist/playlist_screen_controller.dart';
import '/services/stream_service.dart';
import '../ui/widgets/snackbar.dart';
import '/services/permission_service.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
import '../ui/player/player_controller.dart';
import 'discovery/discovery_service.dart';
import 'music_service.dart';
import 'synced_lyrics_service.dart';
import 'download_notice.dart';
import 'download_quality.dart';
import 'wifi_only_downloads.dart';
import 'device_music.dart';
import 'network_kind.dart';
import 'offline_playback.dart';
import 'smart_downloads.dart';
import 'pending_downloads.dart';

/// A song's download broken off, or its stream not had, for want of a
/// connection (or with the connection to blame): it's tried again.
class DownloadInterrupted implements Exception {
  const DownloadInterrupted([this.cause]);

  final Object? cause;

  @override
  String toString() => 'Download interrupted: $cause';
}

class Downloader extends GetxService {
  // receiveTimeout is the max gap between chunks, so a stalled download
  // fails instead of leaving isJobRunning stuck and every later download
  // queued forever. It does not cap the total transfer time.
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  MediaItem? currentSong;
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
  final currentPlaylistId = "".obs;
  final songDownloadingProgress = 0.obs;
  final playlistDownloadingProgress = 0.obs;
  final isJobRunning = false.obs;

  /// Download on Wi-Fi only, on mobile data: the next song waits for Wi-Fi.
  final waitingForWifi = false.obs;

  /// No connection: the next song waits for one, as Spotify's and YouTube
  /// Music's downloads wait for the network.
  final waitingForConnection = false.obs;

  /// A song broken off while there's a connection (it may be changing,
  /// Wi-Fi to mobile data, or the server failing) is tried again after
  /// this, then twice this, before it's passed over.
  @visibleForTesting
  static Duration retryDelay = const Duration(seconds: 2);

  /// Tries of a song broken off with a connection there.
  static const _triesOnline = 3;

  RxList<MediaItem> songQueue = <MediaItem>[].obs;

  /// The queues kept for the next start (PendingDownloads), this long
  /// after they last changed.
  static const keepDelay = Duration(seconds: 1);
  final _keepWorkers = <Worker>[];
  Future<void> _kept = Future.value();

  @override
  void onInit() {
    super.onInit();
    _keepWorkers
      ..add(debounce(songQueue, (_) => _keepPending(), time: keepDelay))
      ..add(debounce(playlistQueue, (_) => _keepPending(), time: keepDelay));
  }

  @override
  void onClose() {
    for (final worker in _keepWorkers) {
      worker.dispose();
    }
    super.onClose();
  }

  void _keepPending() {
    final songs = songQueue.toList();
    final playlists = {
      for (final e in playlistQueue.entries) e.key: e.value.toList()
    };
    _kept = _kept
        .then((_) => PendingDownloads.mirror(songs, playlists))
        .catchError((Object e) => printERROR('Pending downloads: $e'));
  }

  /// Whether the songs can be written now without asking for anything (the
  /// app's own folder, or storage access granted already): resuming at
  /// start must not open a permission prompt.
  Future<bool> canResumeWithoutAsking() async {
    final settings = Get.find<SettingsScreenController>();
    if (!settings.isCurrentPathsupportDownDir &&
        !await PermissionService.hasExtStoragePermission()) {
      return false;
    }
    return checkPermissionNDir();
  }

  bool _pendingMerged = false;

  /// What was left to download when Riff last stopped, back in the queues
  /// (once a run): the playlists' and albums' (shown downloading again) and
  /// the songs on their own, each once.
  void _mergePending() {
    if (_pendingMerged) return;
    _pendingMerged = true;
    final left = PendingDownloads.load(
        isDownloaded: (id) =>
            Hive.isBoxOpen('SongDownloads') &&
            Hive.box('SongDownloads').containsKey(id));
    left.playlists.forEach((id, songs) {
      if (playlistQueue.containsKey(id)) return;
      playlistQueue[id] = songs;
      songQueue.addAll(songs.where((s) => !songQueue.contains(s)));
    });
    songQueue.addAll(left.songs.where((s) => !songQueue.contains(s)));
  }

  /// At start: what was left goes on, as Spotify's downloads do after a
  /// restart. Where that would mean asking for storage access first, it
  /// waits for your next download (which asks) instead.
  Future<void> resumePending() async {
    if (_pendingMerged || PendingDownloads.isEmpty) return;
    if (!await canResumeWithoutAsking()) return;
    _mergePending();
    if (songQueue.isNotEmpty && isJobRunning.isFalse) {
      unawaited(triggerDownloadingJob());
    }
  }

  Future<bool> checkPermissionNDir() async {
    final settingsScreenController = Get.find<SettingsScreenController>();

    if (!settingsScreenController.isCurrentPathsupportDownDir &&
        !await PermissionService.getExtStoragePermission()) {
      _notifyDownloadSetupFailed();
      return false;
    }

    final dirPath =
        Get.find<SettingsScreenController>().downloadLocationPath.string;
    final directory = Directory(dirPath);
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } catch (_) {
      _notifyDownloadSetupFailed();
      return false;
    }
    return true;
  }

  void _notifyDownloadSetupFailed() {
    final ctx = Get.context;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
      ctx,
      'downloadSetupFailed'.tr,
      size: SanckBarSize.MEDIUM,
    ));
  }

  Future<void> downloadPlaylist(
      String playlistId, List<MediaItem> songList) async {
    if (!(await checkPermissionNDir())) return;

    // for toggle between downloading request & cancelling
    if (playlistQueue.containsKey(playlistId)) {
      songQueue.removeWhere((element) => songList.contains(element));
      playlistQueue.remove(playlistId);
      return;
    }

    _mergePending();
    unawaited(SmartDownloads.claim(songList.map((s) => s.id)));
    playlistQueue[playlistId] = songList;
    songQueue.addAll(songList.where((s) => !songQueue.contains(s)));

    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  /// [signal]: a download you chose, a sign of your taste (Smart
  /// downloads' aren't).
  Future<void> download(MediaItem? song,
      {List<MediaItem>? songList, bool signal = true}) async {
    if (!(await checkPermissionNDir())) return;
    _mergePending();
    final discovery = signal && Get.isRegistered<DiscoveryService>()
        ? Get.find<DiscoveryService>()
        : null;
    // Asked for: yours, whatever Smart downloads thought of it.
    if (signal) {
      unawaited(SmartDownloads.claim(
          songList?.map((s) => s.id) ?? [if (song != null) song.id]));
    }
    if (songList != null) {
      songQueue.addAll(songList);
      for (final s in songList) {
        discovery?.onDownload(s);
      }
    } else {
      songQueue.add(song!);
      discovery?.onDownload(song);
    }
    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  /// The song cache's copy of [song], now it's downloaded: its entry, and
  /// its file unless it's playing from it.
  Future<void> _dropCachedCopy(MediaItem song) async {
    if (!Hive.isBoxOpen("SongsCache")) return;
    final cache = Hive.box("SongsCache");
    if (!cache.containsKey(song.id)) return;
    await cache.delete(song.id);
    if (Get.isRegistered<PlayerController>() &&
        Get.find<PlayerController>().currentSong.value?.id == song.id) {
      return;
    }
    try {
      final file = File(
          "${(await getTemporaryDirectory()).path}/cachedSongs/${song.id}.mp3");
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Songs this job has been through, for the downloads' notification.
  int _doneThisJob = 0;

  /// This job said it waits for a connection (once: a connection that
  /// comes and goes doesn't say it each time).
  bool _saidNoConnection = false;

  /// The notification: [text] (the song downloading, or why it waits) and
  /// how many of the job's songs are done.
  void _notice(String text) => DownloadNotice.update(DownloadNotice.songs,
      done: _doneThisJob, total: _doneThisJob + songQueue.length, text: text);

  Future<void> triggerDownloadingJob() async {
    isJobRunning.value = true;
    _doneThisJob = 0;
    _saidNoConnection = false;
    try {
      // Loop (was recursion) until both queues drain.
      do {
        await _runDownloadingJob();
      } while (songQueue.isNotEmpty);
    } catch (e) {
      printERROR("Download job failed: $e");
    } finally {
      // Always release the job flag, or later downloads only ever queue.
      isJobRunning.value = false;
      DownloadNotice.end(DownloadNotice.songs);
      currentSong = null;
      currentPlaylistId.value = "";
      playlistDownloadingProgress.value = 0;
    }
  }

  Future<void> _runDownloadingJob() async {
    //check if playlist download in queue => download playlistsongs else download from general songs queue
    if (playlistQueue.isNotEmpty) {
      for (String playlistId in playlistQueue.keys.toList()) {
        //checked in case download cancel request
        if (playlistQueue.containsKey(playlistId)) {
          currentPlaylistId.value = playlistId;
          await downloadSongList((playlistQueue[playlistId]!).toList(),
              isPlaylist: true);
          if (Get.isRegistered<PlaylistScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<PlaylistScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
          } 
          // in case of album
          else if (Get.isRegistered<AlbumScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<AlbumScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
          }
          playlistQueue.remove(playlistId);
        }
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
      }
    } else {
      await downloadSongList(songQueue.toList());
    }
  }

  void _showSnack(String message) {
    final ctx = Get.context;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(snackbar(ctx, message,
        size: SanckBarSize.BIG,
        duration: const Duration(seconds: 2),
        top: !GetPlatform.isDesktop));
  }

  void _onWaitForWifi() {
    waitingForWifi.value = true;
    _showSnack('downloadsWaitForWifi'.tr);
    // Riff stays up meanwhile, so the downloads start once there's Wi-Fi.
    _notice('waitingForWifi'.tr);
  }

  /// Holds the next song while there's no connection at all, until there's
  /// one (true) or [wanted] says it was called off meanwhile (false).
  Future<bool> _waitForConnection(bool Function() wanted) async {
    if (OfflinePlayback.noConnection.isFalse) return true;
    try {
      waitingForConnection.value = true;
      if (!_saidNoConnection) {
        _saidNoConnection = true;
        _showSnack('downloadsWaitForConnection'.tr);
      }
      // Riff stays up meanwhile, so they go on once it's back.
      _notice('waitingForConnection'.tr);
      while (OfflinePlayback.noConnection.isTrue) {
        if (!wanted()) return false;
        await _nextChange();
      }
      return wanted();
    } finally {
      waitingForConnection.value = false;
    }
  }

  /// Until the connection or the queues change.
  Future<void> _nextChange() {
    final changed = Completer<void>();
    void wake([_]) {
      if (!changed.isCompleted) changed.complete();
    }

    final subscriptions = [
      OfflinePlayback.noConnection.listen(wake),
      songQueue.listen(wake),
      playlistQueue.listen(wake),
    ];
    return changed.future.whenComplete(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });
  }

  bool _isDownloaded(MediaItem song) =>
      Hive.box("SongDownloads").containsKey(song.id);

  /// Downloads [song] once it may (Download on Wi-Fi only) and can (a
  /// connection): broken off for want of one, it waits for it and goes on;
  /// broken off with one there, it's tried again a little later, twice.
  /// False when [wanted] says it was called off meanwhile.
  Future<bool> _downloadWhenConnected(
      MediaItem song, bool Function() wanted) async {
    var brokenOff = 0;
    while (true) {
      // Download on Wi-Fi only: on mobile data, it waits for Wi-Fi.
      final go = await WifiOnlyDownloads.waitForWifi(
          wanted: wanted, onWait: _onWaitForWifi);
      waitingForWifi.value = false;
      if (!go) return false;
      // Broken off as the connection went: that's not the song's fault.
      if (OfflinePlayback.noConnection.isTrue) brokenOff = 0;
      if (!await _waitForConnection(wanted)) return false;
      currentSong = song;
      songDownloadingProgress.value = 0;
      _notice(song.title);
      try {
        await writeFileStream(song);
        return true;
      } on DownloadInterrupted catch (e) {
        printERROR("Download of ${song.id} broken off: $e");
        // Kept already: what broke came after.
        if (_isDownloaded(song)) return true;
        if (OfflinePlayback.noConnection.isFalse) {
          if (++brokenOff >= _triesOnline) {
            _showSnack("downloadError3".tr);
            return true;
          }
          await Future<void>.delayed(retryDelay * brokenOff);
        }
      } catch (e) {
        // Skip this song (it leaves the queue) rather than aborting the job
        // and retrying the same failing song forever.
        printERROR("Download of ${song.id} failed: $e");
        return true;
      }
    }
  }

  Future<void> downloadSongList(List<MediaItem> jobSongList,
      {bool isPlaylist = false}) async {
    for (MediaItem song in jobSongList) {
      // intrrupt downloading task in case of playlist download cancel request
      if (isPlaylist && !playlistQueue.containsKey(currentPlaylistId.value)) {
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
        return;
      }

      // Smart downloads go on Wi-Fi only: on mobile data, one is left for
      // their next look rather than holding up the songs after it.
      final leftForWifi =
          SmartDownloads.isPending(song.id) && await NetworkKind.isMetered();
      // A music file on the phone is there already.
      if (!leftForWifi &&
          !Hive.box("SongDownloads").containsKey(song.id) &&
          !DeviceMusic.isDeviceSong(song)) {
        final go = await _downloadWhenConnected(
            song,
            () => isPlaylist
                ? playlistQueue.containsKey(currentPlaylistId.value)
                : songQueue.contains(song));
        if (!go) {
          // Called off meanwhile (its playlist's download cancelled).
          if (isPlaylist) {
            currentPlaylistId.value = "";
            playlistDownloadingProgress.value = 0;
            return;
          }
          continue;
        }
      }
      songQueue.remove(song);
      _doneThisJob++;
      //for playlist downloading counter update
      if (isPlaylist) {
        playlistDownloadingProgress.value = jobSongList.indexOf(song) + 1;
      }
    }
  }

  /// What a stream not had says when the connection is (or may be) to
  /// blame.
  static const _byConnection = {'networkError', 'streamUnknownError'};

  Future<void> writeFileStream(MediaItem song) async {
    Completer<void> complete = Completer();

    final settingsScreenController = Get.find<SettingsScreenController>();
    final downloadingFormat = settingsScreenController.downloadingFormat.string;

    final playerResponse = await StreamProvider.fetch(song.id);
    if (!playerResponse.playable) {
      if (OfflinePlayback.noConnection.isTrue ||
          _byConnection.contains(playerResponse.statusMSG)) {
        throw DownloadInterrupted(playerResponse.statusMSG);
      }
      _showSnack(playerResponse.statusMSG.tr);
      printINFO("Requested song is not downloadable. You may try again");
      if (!complete.isCompleted) complete.complete();
      return complete.future;
    }

    // Download quality Low: the smallest stream in the format.
    Audio requiredAudioStream = DownloadQuality.low.isTrue
        ? playerResponse.lowestBitrateAudioOf(
            downloadingFormat == "opus" ? Codec.opus : Codec.mp4a)!
        : downloadingFormat == "opus"
            ? playerResponse.highestBitrateOpusAudio!
            : playerResponse.highestBitrateMp4aAudio!;

    final dirPath = settingsScreenController.downloadLocationPath.string;
    final actualDownformat =
        requiredAudioStream.audioCodec.name.contains("mp") ? "m4a" : "opus";
    final RegExp invalidChar =
        RegExp(r'Container.|\/|\\|\"|\<|\>|\*|\?|\:|\!|\[|\]|\¡|\||\%');
    final songTitle = "${song.title.trim()} (${song.artist?.trim()})"
        .replaceAll(invalidChar, "");
    String filePath = "$dirPath/$songTitle.$actualDownformat";
    // Another song of the same title and artist (an album version and the
    // single) keeps its own file: named apart by id.
    if (Hive.box("SongDownloads").values.any(
        (v) => v is Map && v['videoId'] != song.id && v['url'] == filePath)) {
      filePath = "$dirPath/$songTitle ${song.id}.$actualDownformat";
    }
    printINFO("Downloading filePath: $filePath");
    final totalBytes = requiredAudioStream.size;

    _dio.download(
        requiredAudioStream.url,
        options: Options(headers: {"Range": 'bytes=0-$totalBytes'}),
        filePath, onReceiveProgress: (count, total) {
      if (total <= 0) return;
      songDownloadingProgress.value = ((count / total) * 100).toInt();
    }).then(
      (value) async {
        printINFO(value.data);

        String? year;
        try {
          if (song.extras?['year'] != null) {
            year = song.extras?['year'];
          } else {
            if (song.album != null) {
              final musicServ = Get.find<MusicServices>();
              year = await musicServ.getSongYear(song.id);
            }
          }
        } catch (_) {}

        // Save Thumbnail
        try {
          final thumbnailPath =
              "${settingsScreenController.supportDirPath}/thumbnails/${song.id}.png";
          await _dio.downloadUri(song.artUri!, thumbnailPath);
          // ignore: empty_catches
        } catch (e) {}

        song.extras?['url'] = filePath;
        final songJson = MediaItemBuilder.toJson(song);
        final streamInfoJson = requiredAudioStream.toJson();
        streamInfoJson['url'] = filePath;
        // [playbility status, info map]
        songJson["streamInfo"] = [true, streamInfoJson];

        Hive.box("SongDownloads").put(song.id, songJson);
        // Downloaded, it's no longer just cached from listening: one row in
        // Songs, and the cached copy's room back.
        await _dropCachedCopy(song);
        Get.find<LibrarySongsController>().librarySongsList
          ..remove(song)
          ..add(song);
        printINFO("Downloaded successfully");
        // Its lyrics too, to show offline (as Spotify's downloads do).
        unawaited(SyncedLyricsService.keepForOffline(song));

        final trackDetails = "${song.extras?['trackDetails'] ?? ''}".split("/");
        final int? trackNumber = int.tryParse(trackDetails.first);
        final int? totalTracks =
            trackDetails.length > 1 ? int.tryParse(trackDetails[1]) : null;

        try {
          /// Reverted -- Removed AudioTags as using this package, app is flagged as TROJ_GEN.R002V01K623 by TrendMicro-HouseCall
          final imageUrl = song.artUri!.toString();
          Tag tag = Tag(
              title: song.title,
              trackArtist: song.artist,
              album: song.album,
              year: int.tryParse(year ?? ""),
              trackNumber: trackNumber,
              trackTotal: totalTracks,
              albumArtist: song.artist,
              genre: song.genre,
              pictures: [
                Picture(
                    bytes: (await NetworkAssetBundle(Uri.parse((imageUrl)))
                            .load(imageUrl))
                        .buffer
                        .asUint8List(),
                    mimeType: MimeType.png,
                    pictureType: PictureType.coverFront)
              ]);

          await AudioTags.write(filePath, tag);
        } catch (e) {
          printERROR("$e");
        }
        if (!complete.isCompleted) complete.complete();
      },
    ).onError(
      (error, stackTrace) {
        printINFO(
            "Downloading failed due to network/stream error! Please try again");
        if (!complete.isCompleted) {
          complete.completeError(DownloadInterrupted(error));
        }
      },
    );

    return complete.future;
  }
}
