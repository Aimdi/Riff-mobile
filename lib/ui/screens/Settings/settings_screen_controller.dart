import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../utils/update_check_flag_file.dart';
import '/services/piped_service.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '../../../utils/helper.dart';
import '/services/music_service.dart';
import '/services/sponsorblock_service.dart';
import '/services/video_stream_service.dart';
import '/services/yt_auth_service.dart';
import '/ui/player/player_controller.dart';
import '../Home/home_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SettingsScreenController extends GetxController {
  late String _supportDir;
  final cacheSongs = false.obs;
  final setBox = Hive.box("AppPrefs");
  final themeModetype = ThemeType.dynamic.obs;
  final skipSilenceEnabled = false.obs;
  final sponsorBlockEnabled = true.obs;
  final podcastAutoSkipAdsEnabled = true.obs;
  /// AntennaPod-experimental style: auto-advance to the next podcast episode
  /// when one ends (queue or feed list already loaded into the player queue).
  final podcastContinuousPlaybackEnabled = true.obs;
  final loudnessNormalizationEnabled = false.obs;
  final ytConnected = false.obs;
  final playbackSpeed = 1.0.obs;
  final playbackPitch = 1.0.obs;
  // audD API token for Shazam-style song recognition (empty = not configured).
  final auddApiToken = ''.obs;
  final bassBoost = 0.obs;
  final volumeBoostMb = 0.obs;
  final reverbPreset = 0.obs;
  final virtualizer = 0.obs;
  final noOfHomeScreenContent = 3.obs;
  final streamingQuality = AudioQuality.High.obs;
  /// In-player muted video surface (Low = 144–240p, High = ≤720p video-only).
  final videoQuality = VideoQuality.high.obs;
  final playerUi = 0.obs;
  final slidableActionEnabled = true.obs;
  final isIgnoringBatteryOptimizations = false.obs;
  final autoOpenPlayer = false.obs;
  final discoverContentType = "QP".obs;
  final isNewVersionAvailable = false.obs;
  final isLinkedWithPiped = false.obs;
  final stopPlyabackOnSwipeAway = false.obs;
  final currentAppLanguageCode = "en".obs;
  final downloadLocationPath = "".obs;
  final exportLocationPath = "".obs;
  final downloadingFormat = "".obs;
  final autoDownloadFavoriteSongEnabled = false.obs;
  final isTransitionAnimationDisabled = false.obs;
  final backgroundPlayEnabled = true.obs;
  final keepScreenAwake = false.obs;
  final restorePlaybackSession = false.obs;
  final cacheHomeScreenData = true.obs;
  /// Unlocks Advanced developer tools (tap About version 7×).
  final developerMode = false.obs;
  final currentVersion = "V1.7.72";
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  @override
  void onInit() {
    _setInitValue();
    if (updateCheckFlag) _checkNewVersion();
    _createInAppSongDownDir();
    super.onInit();
  }

  get currentVision => currentVersion;
  get isCurrentPathsupportDownDir =>
      "$_supportDir/Music" == downloadLocationPath.toString();
  String get supportDirPath => _supportDir;

  _checkNewVersion() {
    newVersionCheck(currentVersion)
        .then((value) => isNewVersionAvailable.value = value);
  }

  Future<String> _createInAppSongDownDir() async {
    _supportDir = (await getApplicationSupportDirectory()).path;
    final directory = Directory("$_supportDir/Music/");
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return "$_supportDir/Music";
  }

  Future<void> _setInitValue() async {
    final isDesktop = GetPlatform.isDesktop;
    final appLang = setBox.get('currentAppLanguageCode') ?? "en";
    currentAppLanguageCode.value = appLang == "zh_Hant"
        ? "zh-TW"
        : appLang == "zh_Hans"
            ? "zh-CN"
            : appLang;
    // Bottom nav option removed — clear any leftover preference.
    if (setBox.get("isBottomNavBarEnabled") == true) {
      setBox.put("isBottomNavBarEnabled", false);
    }
    noOfHomeScreenContent.value =
        _asInt(setBox.get("noOfHomeScreenContent"), 3);
    isTransitionAnimationDisabled.value =
        setBox.get("isTransitionAnimationDisabled") ?? false;
    cacheSongs.value = setBox.get('cacheSongs') ?? false;
    final themeModeIndex = setBox.get('themeModeType') ?? 2;
    themeModetype.value = (themeModeIndex is int &&
            themeModeIndex >= 0 &&
            themeModeIndex < ThemeType.values.length)
        ? ThemeType.values[themeModeIndex]
        : ThemeType.dark;
    // Never assign Hive null into RxBool — throws and blanks Home startup
    // (SettingsScreenController is first resolved from Home/Player build).
    skipSilenceEnabled.value =
        isDesktop ? false : (setBox.get("skipSilenceEnabled") ?? false);
    sponsorBlockEnabled.value = setBox.get("sponsorBlockEnabled") ?? true;
    podcastAutoSkipAdsEnabled.value =
        setBox.get("podcastAutoSkipAds") ?? true;
    podcastContinuousPlaybackEnabled.value =
        setBox.get("podcastContinuousPlayback") ?? true;
    loudnessNormalizationEnabled.value = isDesktop
        ? false
        : (setBox.get("loudnessNormalizationEnabled") ?? false);
    ytConnected.value = YtAuthService.isConnected;
    playbackSpeed.value = (setBox.get("playbackSpeed") ?? 1.0).toDouble();
    playbackPitch.value = (setBox.get("playbackPitch") ?? 1.0).toDouble();
    auddApiToken.value = setBox.get("auddApiToken") ?? '';
    bassBoost.value = _asInt(setBox.get("bassBoost"), 0);
    volumeBoostMb.value = _asInt(setBox.get("volumeBoostMb"), 0);
    reverbPreset.value = _asInt(setBox.get("reverbPreset"), 0);
    virtualizer.value = _asInt(setBox.get("virtualizer"), 0);
    autoOpenPlayer.value = setBox.get("autoOpenPlayer") ?? true;
    restorePlaybackSession.value =
        setBox.get("restrorePlaybackSession") ?? false;
    cacheHomeScreenData.value = setBox.get("cacheHomeScreenData") ?? true;
    developerMode.value = setBox.get("developerMode") ?? false;
    // Hive may lack this key when AppPrefs is non-empty (partial prefs /
    // upgrade / ClientConfig writes). Indexing AudioQuality.values[null]
    // throws TypeError during onInit and leaves a blank startup screen.
    final streamQIndex = setBox.get('streamingQuality');
    if (streamQIndex is int &&
        streamQIndex >= 0 &&
        streamQIndex < AudioQuality.values.length) {
      streamingQuality.value = AudioQuality.values[streamQIndex];
    } else {
      streamingQuality.value = AudioQuality.High;
      setBox.put('streamingQuality', AudioQuality.High.index);
    }
    final videoQIndex = setBox.get('videoQuality');
    if (videoQIndex is int &&
        videoQIndex >= 0 &&
        videoQIndex < VideoQuality.values.length) {
      videoQuality.value = VideoQuality.values[videoQIndex];
    } else {
      videoQuality.value = VideoQuality.high;
    }
    playerUi.value = isDesktop ? 0 : _asInt(setBox.get('playerUi'), 0);
    backgroundPlayEnabled.value = setBox.get("backgroundPlayEnabled") ?? true;
    keepScreenAwake.value = isDesktop
        ? true
        : (setBox.get("keepScreenAwake") ?? false);
    final downloadPath =
        setBox.get('downloadLocationPath') ?? await _createInAppSongDownDir();
    downloadLocationPath.value =
        (isDesktop && downloadPath.contains("emulated"))
            ? await _createInAppSongDownDir()
            : downloadPath;

    exportLocationPath.value =
        setBox.get("exportLocationPath") ?? "/storage/emulated/0/Music";
    downloadingFormat.value = setBox.get('downloadingFormat') ?? "m4a";
    discoverContentType.value = setBox.get('discoverContentType') ?? "QP";
    slidableActionEnabled.value = setBox.get('slidableActionEnabled') ?? true;
    if (setBox.containsKey("piped")) {
      final piped = setBox.get("piped");
      isLinkedWithPiped.value =
          piped is Map && piped['isLoggedIn'] == true;
    }
    stopPlyabackOnSwipeAway.value =
        setBox.get('stopPlyabackOnSwipeAway') ?? false;
    if (GetPlatform.isAndroid) {
      isIgnoringBatteryOptimizations.value =
          (await Permission.ignoreBatteryOptimizations.isGranted);
    }
    autoDownloadFavoriteSongEnabled.value =
        setBox.get("autoDownloadFavoriteSongEnabled") ?? false;
  }

  /// Coerce Hive numerics into int for RxInt assignments (double/null → fallback).
  static int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  void setAppLanguage(String? val) {
    Get.updateLocale(Locale(val!));
    Get.find<MusicServices>().hlCode = val;
    Get.find<HomeScreenController>().loadContentFromNetwork(silent: true);
    currentAppLanguageCode.value = val;
    setBox.put('currentAppLanguageCode', val);
  }

  void setContentNumber(int? no) {
    noOfHomeScreenContent.value = no!;
    setBox.put("noOfHomeScreenContent", no);
  }

  void setStreamingQuality(dynamic val) {
    setBox.put("streamingQuality", AudioQuality.values.indexOf(val));
    streamingQuality.value = val;
  }

  void setVideoQuality(dynamic val) {
    if (val is! VideoQuality) return;
    setBox.put("videoQuality", VideoQuality.values.indexOf(val));
    videoQuality.value = val;
    VideoStreamService.clearCache();
  }

  void setPlayerUi(dynamic val) {
    final playerCon = Get.find<PlayerController>();
    setBox.put("playerUi", val);
    if (val == 1 && playerCon.gesturePlayerStateAnimationController == null) {
      playerCon.initGesturePlayerStateAnimationController();
    }

    playerUi.value = val;
  }

  void toggleSlidableAction(bool val) {
    setBox.put("slidableActionEnabled", val);
    slidableActionEnabled.value = val;
  }

  void changeDownloadingFormat(String? val) {
    setBox.put("downloadingFormat", val);
    downloadingFormat.value = val!;
  }

  Future<void> setExportedLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select export file folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put("exportLocationPath", pickedFolderPath);
    exportLocationPath.value = pickedFolderPath;
  }

  Future<void> setDownloadLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select downloads folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put("downloadLocationPath", pickedFolderPath);
    downloadLocationPath.value = pickedFolderPath;
  }

  void disableTransitionAnimation(bool val) {
    setBox.put('isTransitionAnimationDisabled', val);
    isTransitionAnimationDisabled.value = val;
  }

  Future<void> clearImagesCache() async {
    final tempImgDirPath =
        "${(await getApplicationCacheDirectory()).path}/libCachedImageData";
    final tempImgDir = Directory(tempImgDirPath);
    try {
      if (await tempImgDir.exists()) {
        await tempImgDir.delete(recursive: true);
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  void resetDownloadLocation() {
    final defaultPath = "$_supportDir/Music";
    setBox.put("downloadLocationPath", defaultPath);
    downloadLocationPath.value = defaultPath;
  }

  void onThemeChange(dynamic val) {
    setBox.put('themeModeType', ThemeType.values.indexOf(val));
    themeModetype.value = val;
    Get.find<ThemeController>().changeThemeModeType(val);
  }

  void onContentChange(dynamic value) {
    setBox.put('discoverContentType', value);
    discoverContentType.value = value;
    Get.find<HomeScreenController>().changeDiscoverContent(value);
  }

  void toggleCachingSongsValue(bool value) {
    setBox.put("cacheSongs", value);
    cacheSongs.value = value;
  }

  void toggleSkipSilence(bool val) {
    Get.find<PlayerController>().toggleSkipSilence(val);
    setBox.put('skipSilenceEnabled', val);
    skipSilenceEnabled.value = val;
  }

  void togglePodcastAutoSkipAds(bool val) {
    setBox.put('podcastAutoSkipAds', val);
    podcastAutoSkipAdsEnabled.value = val;
  }

  void togglePodcastContinuousPlayback(bool val) {
    setBox.put('podcastContinuousPlayback', val);
    podcastContinuousPlaybackEnabled.value = val;
  }

  void toggleSponsorBlock(bool val) {
    setBox.put('sponsorBlockEnabled', val);
    sponsorBlockEnabled.value = val;
    if (Get.isRegistered<SponsorBlockService>()) {
      Get.find<SponsorBlockService>().enabled = val;
      Get.find<SponsorBlockService>().clearCache();
    }
    // Reload segments for current track when re-enabled.
    final player = Get.find<PlayerController>();
    final song = player.currentSong.value;
    if (val && song != null) {
      player.reloadSponsorBlock();
    }
  }

  void toggleLoudnessNormalization(bool val) {
    Get.find<PlayerController>().toggleLoudnessNormalization(val);
    setBox.put("loudnessNormalizationEnabled", val);
    loudnessNormalizationEnabled.value = val;
  }

  void toggleRestorePlaybackSession(bool val) {
    setBox.put("restrorePlaybackSession", val);
    restorePlaybackSession.value = val;
  }

  Future<void> toggleCacheHomeScreenData(bool val) async {
    setBox.put("cacheHomeScreenData", val);
    cacheHomeScreenData.value = val;
    if (!val) {
      Hive.openBox("homeScreenData").then((box) async {
        await box.clear();
        await box.close();
      });
    } else {
      await Hive.openBox("homeScreenData");
      Get.find<HomeScreenController>().cachedHomeScreenData(updateAll: true);
    }
  }

  void toggleAutoDownloadFavoriteSong(bool val) {
    setBox.put("autoDownloadFavoriteSongEnabled", val);
    autoDownloadFavoriteSongEnabled.value = val;
  }

  void toggleBackgroundPlay(bool val) {
    setBox.put('backgroundPlayEnabled', val);
    backgroundPlayEnabled.value = val;
  }

  void toggleKeepScreenAwake(bool val) {
    setBox.put('keepScreenAwake', val);
    keepScreenAwake.value = val;
    try {
        if (val) {
          // enable wakelock immediately if music is playing
          if (Get.find<PlayerController>().buttonState.value ==
              PlayButtonState.playing) {
            WakelockPlus.enable();
          }
        } else {
          WakelockPlus.disable();
        }
     
    } catch (e) {
      // ignore if player/controller not available
    }
  }

  Future<void> enableIgnoringBatteryOptimizations() async {
    await Permission.ignoreBatteryOptimizations.request();
    isIgnoringBatteryOptimizations.value =
        await Permission.ignoreBatteryOptimizations.isGranted;
  }

  void toggleAutoOpenPlayer(bool val) {
    setBox.put('autoOpenPlayer', val);
    autoOpenPlayer.value = val;
  }

  Future<void> unlinkPiped() async {
    Get.find<PipedServices>().logout();
    isLinkedWithPiped.value = false;
    Get.find<LibraryPlaylistsController>().removePipedPlaylists();
    final box = await Hive.openBox('blacklistedPlaylist');
    box.clear();
    ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(Get.context!, "unlinkAlert".tr, size: SanckBarSize.MEDIUM));
    box.close();
  }

  Future<void> resetAppSettingsToDefault() async {
    await setBox.clear();
  }

  /// Returns `true`/`false` when developer mode toggled after 7 taps; else null.
  bool? onVersionLabelTapped() {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;
    if (_versionTapCount < 7) return null;
    _versionTapCount = 0;
    final next = !developerMode.value;
    setDeveloperMode(next);
    return next;
  }

  void setDeveloperMode(bool val) {
    setBox.put('developerMode', val);
    developerMode.value = val;
  }

  void toggleStopPlyabackOnSwipeAway(bool val) {
    setBox.put('stopPlyabackOnSwipeAway', val);
    stopPlyabackOnSwipeAway.value = val;
  }

  Future<void> closeAllDatabases() async {
    await Hive.close();
  }

  Future<String> get dbDir async {
    if (GetPlatform.isDesktop) {
      return "$supportDirPath/db";
    } else {
      return (await getApplicationDocumentsDirectory()).path;
    }
  }
}
