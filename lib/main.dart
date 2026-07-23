import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/player/video_mode_controller.dart';
import '/ui/screens/Search/search_screen_controller.dart';
import '/utils/get_localization.dart';
import '/services/downloader.dart';
import '/services/piped_service.dart';
import '/services/sponsorblock_service.dart';
import '/services/spotify_import_service.dart';
import '/services/audiobookshelf_service.dart';
import '/services/cloud_music_service.dart';
import '/services/plugin_service.dart';
import '/services/soul_sync_service.dart';
import '/services/soulseek_service.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import '/services/client_config_service.dart';
import '/services/discovery/discovery_service.dart';
import '/services/music_service.dart';
import '/services/playback_rules_service.dart';
import '/services/playlist_mix_service.dart';
import '/services/smart_queue_service.dart';
import '/services/track_analysis_service.dart';
import '/ui/home.dart';
import '/ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'ui/screens/Podcasts/podcasts_library_controller.dart';
import 'ui/screens/Podcasts/podcast_queue_controller.dart';
import 'ui/screens/Podcasts/podcast_folder_controller.dart';
import 'ui/screens/Audiobooks/audiobook_library_controller.dart';
import 'utils/system_tray.dart';
import 'utils/update_check_flag_file.dart';
import 'utils/helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Video mode's mpv engine. In the lite (audio-only) APK the library is
  // stripped: init throws, the flag stays false and video mode hides.
  try {
    MediaKit.ensureInitialized();
    VideoModeController.engineAvailable = true;
  } catch (e) {
    debugPrint('MediaKit init skipped (lite build?): $e');
  }
  // Critical boxes only — open the rest after first frame so cold start
  // isn't stuck on ~18 sequential Hive opens + discovery network work.
  await initHiveCritical();
  _setAppInitPrefs();
  // Load cached remote client config synchronously; refresh in background.
  unawaited(ClientConfigService.init());
  startApplicationServices();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  TerminateRestart.instance.initialize();
  runApp(const MyApp());
  // Warm the rest after the first frame is scheduled.
  unawaited(_warmAfterFirstFrame());
}

/// Non-critical Hive boxes + discovery / audio-session setup.
/// Kept off the critical path so Home can paint from cache immediately.
Future<void> _warmAfterFirstFrame() async {
  try {
    await initHiveDeferred();
    if (!Get.isRegistered<DiscoveryService>()) {
      await Get.putAsync(() => DiscoveryService().init(), permanent: true);
    }
    if (!GetPlatform.isDesktop && !Get.isRegistered<PlaybackRulesService>()) {
      await Get.putAsync(() => PlaybackRulesService().init(), permanent: true);
    }
    if (!Get.isRegistered<SmartQueueService>()) {
      Get.put(SmartQueueService().init(), permanent: true);
    }
  } catch (e) {
    // Never block the UI on background warm-up failures.
    printERROR('Background warm-up failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if (!GetPlatform.isDesktop) Get.put(AppLinksController());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return GetMaterialApp(
        title: 'Riff',
        home: const Home(),
        debugShowCheckedModeBanner: false,
        translations: Languages(),
        locale:
            Locale(Hive.box("AppPrefs").get('currentAppLanguageCode') ?? "en"),
        fallbackLocale: const Locale("en"),
        builder: (context, child) {
          final mQuery = MediaQuery.of(context);
          final scale =
              mQuery.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.1);
          return Stack(
            children: [
              GetX<ThemeController>(
                builder: (controller) => MediaQuery(
                  data: mQuery.copyWith(textScaler: scale),
                  child: AnimatedTheme(
                      duration: const Duration(milliseconds: 700),
                      // Never bang-null: a missing theme must not black-screen.
                      data: controller.themedata.value ??
                          ThemeData(
                            brightness: Brightness.dark,
                            canvasColor: Colors.black,
                            scaffoldBackgroundColor: Colors.black,
                          ),
                      child: child!),
                ),
              ),
              GestureDetector(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Colors.transparent,
                    height: mQuery.padding.bottom,
                    width: mQuery.size.width,
                  ),
                ),
              )
            ],
          );
        });
  }
}

Future<void> startApplicationServices() async {
  Get.lazyPut(() => PipedServices(), fenix: true);
  Get.lazyPut(() => MusicServices(), fenix: true);
  Get.lazyPut(() => SponsorBlockService(), fenix: true);
  Get.lazyPut(() => SpotifyImportService(), fenix: true);
  Get.lazyPut(() => AudiobookshelfService(), fenix: true);
  Get.lazyPut(() => CloudMusicService(), fenix: true);
  Get.lazyPut(() => PluginService(), fenix: true);
  Get.lazyPut(() => SoulSyncService(), fenix: true);
  Get.lazyPut(() => SoulseekService(), fenix: true);
  Get.lazyPut(() => TrackAnalysisService(), fenix: true);
  Get.lazyPut(() => PlaylistMixService(), fenix: true);
  Get.lazyPut(() => ThemeController(), fenix: true);
  Get.lazyPut(() => PlayerController(), fenix: true);
  Get.lazyPut(() => VideoModeController(), fenix: true);
  Get.lazyPut(() => HomeScreenController(), fenix: true);
  Get.lazyPut(() => LibrarySongsController(), fenix: true);
  Get.lazyPut(() => LibraryPlaylistsController(), fenix: true);
  Get.lazyPut(() => LibraryAlbumsController(), fenix: true);
  Get.lazyPut(() => LibraryArtistsController(), fenix: true);
  Get.lazyPut(() => LibraryPodcastsController(), fenix: true);
  Get.lazyPut(() => PodcastQueueController(), fenix: true);
  Get.lazyPut(() => PodcastFolderController(), fenix: true);
  Get.lazyPut(() => AudiobookLibraryController(), fenix: true);
  Get.lazyPut(() => SettingsScreenController(), fenix: true);
  Get.lazyPut(() => Downloader(), fenix: true);
  if (GetPlatform.isDesktop) {
    Get.lazyPut(() => SearchScreenController(), fenix: true);
    Get.put(DesktopSystemTray());
  }
}

initHiveCritical() async {
  String applicationDataDirectoryPath;
  if (GetPlatform.isDesktop) {
    applicationDataDirectoryPath =
        "${(await getApplicationSupportDirectory()).path}/db";
  } else {
    applicationDataDirectoryPath =
        (await getApplicationDocumentsDirectory()).path;
  }
  await Hive.initFlutter(applicationDataDirectoryPath);
  // Needed before first paint / first play. Open in parallel.
  await Future.wait([
    Hive.openBox("SongsCache"),
    Hive.openBox("SongDownloads"),
    Hive.openBox('SongsUrlCache'),
    // Hive box names are case-insensitive (files are lowercased). Never open /
    // delete "appPrefs" separately from "AppPrefs" — that wipes prefs and can
    // black-screen the app on launch (v1.7.82 regression).
    Hive.openBox("AppPrefs"),
    // Home filters touch bans as soon as network content arrives.
    Hive.openBox("BannedSongs"),
    Hive.openBox("BannedArtists"),
    Hive.openBox("BannedCollections"),
  ]);
}

/// Secondary boxes used by podcasts, stats, bans, discovery — not first paint.
initHiveDeferred() async {
  await Future.wait([
    Hive.openBox("PodcastSubs"),
    Hive.openBox("SongStats"),
    Hive.openBox("DailyStats"),
    Hive.openBox("SquareCovers"),
    Hive.openBox("PodcastQueue"),
    Hive.openBox("PodcastFolders"),
    Hive.openBox("SavedAudiobooks"),
    Hive.openBox("PodcastDownloads"),
    Hive.openBox("PodcastProgress"),
    Hive.openBox("TrackAnalysisCache"),
    Hive.openBox("PlaylistMixPrefs"),
  ]);
}

/// Full open (tests / tools). Prefer [initHiveCritical] + [initHiveDeferred].
initHive() async {
  await initHiveCritical();
  await initHiveDeferred();
}

void _setAppInitPrefs() {
  final appPrefs = Hive.box("AppPrefs");
  if (appPrefs.isEmpty) {
    appPrefs.putAll({
      'themeModeType': 2,
      "cacheSongs": false,
      "skipSilenceEnabled": false,
      "sponsorBlockEnabled": true,
      'streamingQuality': 1,
      'themePrimaryColor': 4278199603,
      'discoverContentType': "QP",
      'newVersionVisibility': updateCheckFlag,
      "cacheHomeScreenData": true
    });
    return;
  }
  // Non-empty boxes from upgrades / partial writes may omit keys that
  // SettingsScreenController indexes without a null default on startup.
  if (!appPrefs.containsKey('streamingQuality')) {
    appPrefs.put('streamingQuality', 1);
  }
  if (!appPrefs.containsKey('skipSilenceEnabled')) {
    appPrefs.put('skipSilenceEnabled', false);
  }
  if (!appPrefs.containsKey('themeModeType')) {
    appPrefs.put('themeModeType', 2);
  }
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Defer mix regen so resume doesn't compete with Home/play network.
      if (Get.isRegistered<DiscoveryService>()) {
        Future<void>.delayed(const Duration(seconds: 6), () {
          if (Get.isRegistered<DiscoveryService>()) {
            unawaited(Get.find<DiscoveryService>().maybeRegenerateMixes());
          }
        });
      }
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}
