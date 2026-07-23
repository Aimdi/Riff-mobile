import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';

import 'package:harmonymusic/ui/screens/Artists/artist_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen.dart';

import 'screens/Album/album_screen.dart';
import 'screens/Playlist/playlist_screen.dart';
import 'screens/Search/search_result_screen.dart';
import 'screens/Search/search_screen.dart';
import 'screens/Stats/stats_screen.dart';
import 'screens/Stats/rewind_screen.dart';
import 'screens/Podcasts/podcasts_screen.dart';
import 'screens/Plugins/plugins_screen.dart';
import 'screens/Plugins/torrent_search_screen.dart';
import 'screens/Plugins/soul_sync_screen.dart';
import 'screens/Plugins/seeker_screen.dart';

class ScreenNavigationSetup {
  ScreenNavigationSetup._();

  static const id = 1;
  static const homeScreen = '/homeScreen';
  static const searchScreen = '/searchScreen';
  static const searchResultScreen = '/searchResultScreen';
  static const artistScreen = '/artistScreen';
  static const albumScreen = '/albumScreen';
  static const playlistScreen = '/playlistScreen';
  static const statsScreen = '/statsScreen';
  static const rewindScreen = '/rewindScreen';
  static const podcastsScreen = '/podcastsScreen';
  static const pluginsScreen = '/pluginsScreen';
  static const torrentSearchScreen = '/torrentSearchScreen';
  static const soulSyncScreen = '/soulSyncScreen';
  static const seekerScreen = '/seekerScreen';
}

class ScreenNavigation extends StatelessWidget {
  const ScreenNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
        key: Get.nestedKey(ScreenNavigationSetup.id),
        initialRoute: '/homeScreen',
        onGenerateRoute: (settings) {
          Get.routing.args = settings.arguments;
          switch (settings.name) {

            case ScreenNavigationSetup.homeScreen:
              return GetPageRoute(
                  page: () => const HomeScreen(), settings: settings);
            
            case ScreenNavigationSetup.albumScreen:
              final id = (settings.arguments as (Album?, String)).$2;
              return GetPageRoute(
                  page: () => AlbumScreen(
                        key: Key(id),
                      ),
                  settings: settings);
            
            case ScreenNavigationSetup.playlistScreen:
             final id = (settings.arguments as List)[1] as String;
              return GetPageRoute(
                  page: () => PlaylistScreen(
                        key: Key(id),
                      ),
                  settings: settings);
            
            case ScreenNavigationSetup.statsScreen:
              return GetPageRoute(
                  page: () => const StatsScreen(), settings: settings);

            case ScreenNavigationSetup.rewindScreen:
              return GetPageRoute(
                  page: () => const RewindScreen(), settings: settings);

            case ScreenNavigationSetup.podcastsScreen:
              return GetPageRoute(
                  page: () => const PodcastsScreen(), settings: settings);

            case ScreenNavigationSetup.pluginsScreen:
              return GetPageRoute(
                  page: () => const PluginsScreen(), settings: settings);

            case ScreenNavigationSetup.torrentSearchScreen:
              final args = settings.arguments;
              final initialQuery = args is String
                  ? args
                  : (args is Map ? '${args['query'] ?? ''}' : null);
              return GetPageRoute(
                  page: () => TorrentSearchScreen(
                        initialQuery: (initialQuery ?? '').trim().isEmpty
                            ? null
                            : initialQuery!.trim(),
                      ),
                  settings: settings);

            case ScreenNavigationSetup.soulSyncScreen:
              return GetPageRoute(
                  page: () => const SoulSyncScreen(), settings: settings);

            case ScreenNavigationSetup.seekerScreen:
              final args = settings.arguments;
              final initialQuery = args is String
                  ? args
                  : (args is Map ? '${args['query'] ?? ''}' : null);
              return GetPageRoute(
                  page: () => SeekerScreen(
                        initialQuery: (initialQuery ?? '').trim().isEmpty
                            ? null
                            : initialQuery!.trim(),
                      ),
                  settings: settings);

            case ScreenNavigationSetup.searchScreen:
              return GetPageRoute(
                  page: () => const SearchScreen(), settings: settings);
            
            case ScreenNavigationSetup.searchResultScreen:
              return GetPageRoute(
                  page: () => const SearchResultScreen(), settings: settings);
            
            case ScreenNavigationSetup.artistScreen:
              final args = settings.arguments as List;
              final id = args[0] ? args[1] : (args[1] as Artist).browseId;
              return GetPageRoute(
                  page: () => ArtistScreen(
                        key: Key(id),
                      ),
                  settings: settings);
            
            default:
              return null;
          }
        });
  }
}
