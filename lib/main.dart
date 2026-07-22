import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/screens/Search/search_screen_controller.dart';
import '/utils/get_localization.dart';
import '/services/downloader.dart';
import '/services/piped_service.dart';
import '/services/sponsorblock_service.dart';
import '/services/spotify_import_service.dart';
import '/services/audiobookshelf_service.dart';
import '/services/cloud_music_service.dart';
import '/services/plugin_service.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import '/services/client_config_service.dart';
import '/services/discovery/discovery_service.dart';
import '/services/music_service.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  _setAppInitPrefs();
  // Load cached remote client config synchronously; refresh in background.
  unawaited(ClientConfigService.init());
  startApplicationServices();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  // Discovery depends on MusicServices — init after services are registered.
  await Get.putAsync(() => DiscoveryService().init(), permanent: true);
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  TerminateRestart.instance.initialize();
  runApp(const MyApp());
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
                      data: controller.themedata.value!,
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
  Get.lazyPut(() => ThemeController(), fenix: true);
  Get.lazyPut(() => PlayerController(), fenix: true);
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

initHive() async {
  String applicationDataDirectoryPath;
  if (GetPlatform.isDesktop) {
    applicationDataDirectoryPath =
        "${(await getApplicationSupportDirectory()).path}/db";
  } else {
    applicationDataDirectoryPath =
        (await getApplicationDocumentsDirectory()).path;
  }
  await Hive.initFlutter(applicationDataDirectoryPath);
  await Hive.openBox("SongsCache");
  await Hive.openBox("SongDownloads");
  await Hive.openBox('SongsUrlCache');
  await Hive.openBox("AppPrefs");
  await Hive.openBox("BannedSongs");
  await Hive.openBox("BannedArtists");
  await Hive.openBox("BannedCollections");
  await Hive.openBox("PodcastSubs");
  await Hive.openBox("SongStats");
  await Hive.openBox("DailyStats");
  await Hive.openBox("SquareCovers");
  await Hive.openBox("PodcastQueue");
  await Hive.openBox("PodcastFolders");
  await Hive.openBox("SavedAudiobooks");
  await Hive.openBox("PodcastDownloads");
  await Hive.openBox("PodcastProgress");
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
  }
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Cheap mix regeneration check (no WorkManager in v1).
      if (Get.isRegistered<DiscoveryService>()) {
        unawaited(Get.find<DiscoveryService>().maybeRegenerateMixes());
      }
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}

