import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';

import 'package:harmonymusic/ui/screens/Artists/artist_screen.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'screens/Home/explore_screen.dart';
import 'screens/Home/home_layout_screen.dart';
import 'screens/Home/home_screen.dart';

import 'screens/Album/album_screen.dart';
import 'screens/Playlist/playlist_screen.dart';
import 'screens/Search/search_result_screen.dart';
import 'screens/Search/search_screen.dart';
import 'screens/Stats/stats_screen.dart';
import 'screens/Stats/rewind_screen.dart';
import 'screens/Podcasts/podcasts_library.dart';
import 'screens/Podcasts/podcast_settings_screen.dart';
import 'screens/Podcasts/podcast_stats_screen.dart';
import 'screens/Settings/blacklist_screen.dart';
import 'screens/Settings/gpodder_sync_screen.dart';
import 'screens/Settings/webdav_sync_screen.dart';
import 'screens/Plugins/spotify_pages.dart';
import 'screens/Plugins/plugins_screen.dart';
import '/ui/screens/Plugins/spotify_bridge_screen.dart';
import 'screens/Plugins/torrent_search_screen.dart';
import 'screens/Plugins/soul_sync_screen.dart';
import 'screens/Plugins/seeker_screen.dart';
import 'screens/Recognize/recognize_screen.dart';

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
  static const spotifyBridgeScreen = '/spotifyBridgeScreen';
  static const exploreScreen = '/exploreScreen';
  static const homeLayoutScreen = '/homeLayoutScreen';
  static const podcastSettingsScreen = '/podcastSettingsScreen';
  static const podcastStatsScreen = '/podcastStatsScreen';
  static const blacklistScreen = '/blacklistScreen';
  static const webDavSyncScreen = '/webDavSyncScreen';
  static const gpodderSyncScreen = '/gpodderSyncScreen';
  static const spotifyPageScreen = '/spotifyPageScreen';
  static const recognizeScreen = '/recognizeScreen';
}

/// A page on the nested navigator: the platform's own transition (zoom on
/// Android), in and out at Riff's page timing (§4.7) rather than
/// GetPageRoute's 300 ms.
GetPageRoute<dynamic> _page(
        {required GetPageBuilder page, required RouteSettings settings}) =>
    GetPageRoute<dynamic>(
        page: page, settings: settings, transitionDuration: RiffDurations.page);

class ScreenNavigation extends StatefulWidget {
  const ScreenNavigation({super.key});

  @override
  State<ScreenNavigation> createState() => _ScreenNavigationState();
}

class _ScreenNavigationState extends State<ScreenNavigation> {
  /// Flies a tapped card's cover to the page it opens (CoverHero), along
  /// Material's arc, as MaterialApp's own navigator would.
  final _heroes = HeroController(
      createRectTween: (begin, end) =>
          MaterialRectArcTween(begin: begin, end: end));

  @override
  void dispose() {
    _heroes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
        key: Get.nestedKey(ScreenNavigationSetup.id),
        observers: [_heroes],
        initialRoute: '/homeScreen',
        onGenerateRoute: (settings) {
          Get.routing.args = settings.arguments;
          switch (settings.name) {
            case ScreenNavigationSetup.homeScreen:
              return _page(page: () => const HomeScreen(), settings: settings);

            case ScreenNavigationSetup.albumScreen:
              final id = (settings.arguments as (Album?, String)).$2;
              return _page(
                  page: () => AlbumScreen(
                        key: Key(id),
                      ),
                  settings: settings);

            case ScreenNavigationSetup.playlistScreen:
              final id = (settings.arguments as List)[1] as String;
              return _page(
                  page: () => PlaylistScreen(
                        key: Key(id),
                      ),
                  settings: settings);

            case ScreenNavigationSetup.statsScreen:
              return _page(page: () => const StatsScreen(), settings: settings);

            case ScreenNavigationSetup.rewindScreen:
              return _page(
                  page: () => const RewindScreen(), settings: settings);

            case ScreenNavigationSetup.podcastsScreen:
              return _page(
                  page: () => const PodcastsLibraryWidget(),
                  settings: settings);

            case ScreenNavigationSetup.pluginsScreen:
              return _page(
                  page: () => const PluginsScreen(), settings: settings);

            case ScreenNavigationSetup.torrentSearchScreen:
              final args = settings.arguments;
              final initialQuery = args is String
                  ? args
                  : (args is Map ? '${args['query'] ?? ''}' : null);
              return _page(
                  page: () => TorrentSearchScreen(
                        initialQuery: (initialQuery ?? '').trim().isEmpty
                            ? null
                            : initialQuery!.trim(),
                      ),
                  settings: settings);

            case ScreenNavigationSetup.spotifyBridgeScreen:
              return _page(
                  page: () => const SpotifyBridgeScreen(), settings: settings);

            case ScreenNavigationSetup.spotifyPageScreen:
              final args = settings.arguments as SpotifyPageArgs;
              return _page(
                  page: () => SpotifyPage(args: args), settings: settings);

            case ScreenNavigationSetup.soulSyncScreen:
              return _page(
                  page: () => const SoulSyncScreen(), settings: settings);

            case ScreenNavigationSetup.seekerScreen:
              final args = settings.arguments;
              final initialQuery = args is String
                  ? args
                  : (args is Map ? '${args['query'] ?? ''}' : null);
              return _page(
                  page: () => SeekerScreen(
                        initialQuery: (initialQuery ?? '').trim().isEmpty
                            ? null
                            : initialQuery!.trim(),
                      ),
                  settings: settings);

            case ScreenNavigationSetup.recognizeScreen:
              return _page(
                  page: () => const RecognizeScreen(), settings: settings);

            case ScreenNavigationSetup.exploreScreen:
              final focus = settings.arguments is String
                  ? settings.arguments as String
                  : null;
              return _page(
                  page: () => ExploreScreen(focusTitle: focus),
                  settings: settings);

            case ScreenNavigationSetup.podcastSettingsScreen:
              return _page(
                  page: () => const PodcastSettingsScreen(),
                  settings: settings);

            case ScreenNavigationSetup.blacklistScreen:
              return _page(
                  page: () => const BlacklistScreen(), settings: settings);

            case ScreenNavigationSetup.webDavSyncScreen:
              return _page(
                  page: () => const WebDavSyncScreen(), settings: settings);

            case ScreenNavigationSetup.gpodderSyncScreen:
              return _page(
                  page: () => const GpodderSyncScreen(), settings: settings);

            case ScreenNavigationSetup.podcastStatsScreen:
              return _page(
                  page: () => const PodcastStatsScreen(), settings: settings);

            case ScreenNavigationSetup.homeLayoutScreen:
              return _page(
                  page: () => const HomeLayoutScreen(), settings: settings);

            case ScreenNavigationSetup.searchScreen:
              return _page(
                  page: () => const SearchScreen(), settings: settings);

            case ScreenNavigationSetup.searchResultScreen:
              return _page(
                  page: () => const SearchResultScreen(), settings: settings);

            case ScreenNavigationSetup.artistScreen:
              final args = settings.arguments as List;
              final id = args[0] ? args[1] : (args[1] as Artist).browseId;
              return _page(
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
