import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/models/home_chip.dart';
import 'package:harmonymusic/models/home_shelf_content.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/models/quick_picks.dart';
import 'package:harmonymusic/models/shelf_header.dart';
import 'package:harmonymusic/services/audiobookshelf_service.dart';
import 'package:harmonymusic/services/cloud_music_service.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/piped_service.dart';
import 'package:harmonymusic/services/playlist_mix_service.dart';
import 'package:harmonymusic/services/plugin_service.dart';
import 'package:harmonymusic/services/podcast_inbox_counts.dart';
import 'package:harmonymusic/services/podcast_inbox_cache.dart'
    show podcastPlayerTint;
import 'package:harmonymusic/services/search_suggestions.dart';
import 'package:harmonymusic/services/soul_sync_service.dart';
import 'package:harmonymusic/services/soulseek_service.dart';
import 'package:harmonymusic/services/sponsorblock_service.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:harmonymusic/services/track_analysis_service.dart';
import 'package:harmonymusic/ui/player/components/cover_palette.dart';
import 'package:harmonymusic/ui/player/components/podcast_player_tint.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/player/video_mode_controller.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_library_controller.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_folder_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';

import '../../test/fakes/fake_music_services.dart';
import 'covers.dart';
import 'env.dart';
import 'media_data.dart';
import 'sample_data.dart';

// The app's own controllers, with start-up work that needs the network,
// the audio service or the file system left out (onInit), so their real
// fields and getters are what the screens read. Data is put in by
// [registerShotControllers] or comes from the seeded Hive boxes.
//
// The onInit overrides skip super on purpose: super is the real start-up.
// ignore_for_file: must_call_super

/// The player with nothing behind it: no audio handler, no workers. A
/// song is "playing" because [currentSong] and [buttonState] say so.
class ShotPlayerController extends PlayerController {
  @override
  void onInit() {}
}

class ShotSettingsController extends SettingsScreenController {
  @override
  void onInit() {
    themeModetype.value = ThemeType.dark;
    autoOpenPlayer.value = true;
    restorePlaybackSession.value = true;
  }

  @override
  String get supportDirPath => shotTmp.path;
}

class ShotHomeController extends HomeScreenController {
  @override
  void onInit() {}
}

/// Songs tab: the library songs straight from the seeded boxes (the real
/// init also lists the song cache folder and runs house keeping).
class ShotLibrarySongsController extends LibrarySongsController {
  @override
  Future<void> init() async {
    librarySongsList.assignAll(ShotData.songs(0, 22));
  }
}

/// Podcasts: the followed YouTube shows from the seeded box, and the Inbox
/// as if just fetched (the real one reads every feed over the network).
class ShotPodcastsController extends LibraryPodcastsController {
  @override
  void onInit() {
    // As refreshLib reads them, but now: the Inbox keys its cache by them
    // on its first build.
    libraryPodcasts.assignAll([
      for (final v in Hive.box('LibraryPodcasts').values) Playlist.fromJson(v)
    ]);
    final episodes = ShotPods.inbox;
    inboxEpisodes = episodes;
    inboxSubsKey = ShotPods.subsKey;
    inboxFetchedAt = DateTime.now();
    PodcastInboxCounts.setInbox(episodes);
  }
}

/// Riff's mixes and "Because you played" rows, without the taste model;
/// its repository reads the in-memory boxes (Stats asks it for events).
class ShotDiscoveryService extends DiscoveryService {
  @override
  void onInit() {
    repo = DiscoveryRepository();
  }
}

/// An Audiobookshelf server that is signed in, with a library of books.
class ShotAudiobookshelfService extends AudiobookshelfService {
  @override
  void onInit() {
    isConnected.value = true;
    host.value = ShotBooks.absHost;
    username.value = 'alex';
    libraries.assignAll([AbsLibrary(id: 'lib1', name: 'Audiobooks')]);
    selectedLibraryId.value = 'lib1';
    books.assignAll(ShotBooks.absBooks);
    inProgressBooks.assignAll([
      for (final b in ShotBooks.absBooks)
        if ((b.progress ?? 0) > 0 && (b.progress ?? 0) < 1) b
    ]);
  }

  @override
  String? get token => 'shot-token';

  @override
  String coverUrl(String itemId, {int width = 400}) =>
      '${host.value}/api/items/$itemId/cover?width=$width';

  @override
  String streamUrl(String contentUrl) => '${host.value}$contentUrl';

  @override
  Future<void> fetchLibraries() async {}

  @override
  Future<void> fetchBooks(
      {int page = 0,
      int limit = 50,
      int maxPages = 40,
      String? libraryId}) async {}

  @override
  Future<void> fetchInProgress() async {}

  @override
  Future<AbsBookDetail> fetchBookDetail(String itemId) async =>
      ShotBooks.absDetail(itemId);
}

/// YouTube Music answered from [ShotData] (the album page, a playlist,
/// a podcast show, search).
class ShotMusicServices extends FakeMusicServices {
  @override
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int? limit,
      bool related = false,
      int suggestionsLimit = 0}) async {
    playlistCalls++;
    if (albumId != null) {
      final album = ShotData.albums.firstWhere((a) => a.browseId == albumId,
          orElse: () => ShotData.album(0));
      return {
        ...album.toJson(),
        'browseId': albumId,
        'type': album.description,
        'trackCount': ShotData.albumTracks(album.title).length,
        'tracks': ShotData.albumTracks(album.title),
      };
    }
    final id = playlistId ?? '';
    if (id.startsWith('MPSP')) {
      final show = [
        ShotPods.ytShow(0),
        ShotPods.ytShow(1)
      ].firstWhere((s) => s.playlistId == id, orElse: () => ShotPods.ytShow(0));
      return {
        ...show.toJson(),
        'kind': 'podcast',
        'thumbnails': [
          {'url': show.thumbnailUrl}
        ],
        'tracks': ShotPods.ytEpisodes(show),
      };
    }
    final playlist = ShotData.ytPlaylists.firstWhere((p) => p.playlistId == id,
        orElse: () => ShotData.ytPlaylist(0));
    return {
      ...playlist.toJson(),
      'author': 'YouTube Music',
      'tracks': ShotData.songs(20, 44),
    };
  }

  /// Nova Hart's page: popular songs, shelves, related artists, About.
  @override
  Future<Map<String, dynamic>> getArtist(String channelId) async {
    final artist = ShotData.artists.firstWhere((a) => a.browseId == channelId,
        orElse: () => ShotData.artists[0]);
    final songs = ShotData.songs(0, ShotData.songCount)
        .where((s) => s.artist == artist.name)
        .toList();
    return {
      'name': artist.name,
      'description': '${artist.name} writes night-drive pop: big synths, '
          'small rooms and songs about leaving town. Coastlines, the 2024 '
          'album, was made in a week in a borrowed beach house.',
      'views': '48,215,904 views',
      'channelId': artist.browseId,
      'shuffleId': null,
      'radioId': null,
      'subscribers': '2.4M',
      'thumbnails': [
        {'url': artist.thumbnailUrl, 'width': 544, 'height': 544}
      ],
      'Top songs': {
        'browseId': 'VLriffTop',
        'params': 'top',
        'content': [...songs, ...ShotData.songs(20, 26)],
      },
      'Albums': {
        'browseId': artist.browseId,
        'params': 'albums',
        'content': [
          for (final i in [0, 4, 9, 13]) ShotData.album(i)
        ],
      },
      'Singles & EPs': {
        'content': [
          for (final i in [10, 3, 12]) ShotData.album(i)
        ],
      },
      'Videos': {'content': ShotData.songs(38, 42)},
      'Featured': {
        'content': [for (var i = 0; i < 5; i++) ShotData.ytPlaylist(i)],
      },
      'Related': {
        'content': ShotData.artists.sublist(1, 9),
      },
    };
  }

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    final songs = ShotData.songs(0, 70)
        .where((s) =>
            s.artist == 'Nova Hart' ||
            s.title.toLowerCase().contains('night') ||
            s.title.toLowerCase().contains('lights'))
        .toList();
    final albums = [ShotData.album(0), ShotData.album(4), ShotData.album(9)];
    final artists = [
      ShotData.artists[0],
      ShotData.artists[12],
      ShotData.artists[4],
    ];
    final playlists = [
      ShotData.ytPlaylist(0),
      ShotData.ytPlaylist(8),
      ShotData.ytPlaylist(2),
    ];
    final all = <String, dynamic>{
      'Songs': songs,
      'Albums': albums,
      'Artists': artists,
      'Community playlists': playlists,
      'Videos': ShotData.songs(38, 42),
      'params': null,
    };
    if (filter == null) {
      return {...all, 'topResult': ShotData.artists[0]};
    }
    final key = all.keys.firstWhere(
        (k) => k.replaceAll(' ', '_').toLowerCase() == filter,
        orElse: () => 'Songs');
    return {key: all[key], 'params': null};
  }

  @override
  Future<List<String>> getSearchSuggestion(String queryStr) async => [
        queryStr,
        '$queryStr live',
        '$queryStr acoustic',
        '$queryStr remix',
        '$queryStr lyrics',
      ];

  @override
  Future<SearchSuggestions> getSearchSuggestions(String queryStr) async =>
      SearchSuggestions(
          queries: await getSearchSuggestion(queryStr),
          items: [ShotData.artists[0], ShotData.song(11), ShotData.album(0)]);

  @override
  Future<Map<String, dynamic>> getPodcastDiscovery() async =>
      {'featuredPodcasts': const []};
}

/// Puts the app's controllers and services in place, filled with the
/// sample data: a song playing from a queue, a Home feed, the library.
void registerShotControllers() {
  Get.put<MusicServices>(ShotMusicServices(), permanent: true);
  Get.put<ThemeController>(ThemeController(), permanent: true);
  Get.put<SettingsScreenController>(ShotSettingsController(), permanent: true);

  final player = ShotPlayerController();
  Get.put<PlayerController>(player, permanent: true);
  final queue = ShotData.songs(0, 14);
  player.initFlagForPlayer = false;
  player.currentQueue.assignAll(queue);
  player.currentSongIndex.value = 0;
  player.currentSong.value = queue.first;
  player.buttonState.value = PlayButtonState.playing;
  player.playinfrom.value = PlaylingFrom(
      type: PlaylingFromType.PLAYLIST, name: ShotData.userPlaylist(0).title);
  final total = queue.first.duration ?? const Duration(minutes: 3);
  player.progressBarStatus.value = ProgressBarState(
      current: total * 0.38, buffered: total * 0.72, total: total);

  prefillCoverColors(queue);

  final discovery = ShotDiscoveryService();
  Get.put<DiscoveryService>(discovery, permanent: true);
  discovery.dailyMixes.assignAll(ShotData.dailyMixes);
  discovery.personalSections.assignAll([
    DiscoverySection(
      id: 'because_nova',
      title: 'Because you liked Paper Planes Over Lisbon',
      reason: '',
      tracks: [for (var i = 31; i < 39; i++) ShotData.songJson(i)],
      seed: ShotData.songJson(0),
    ),
  ]);
  discovery.isReady.value = true;
  // The Inbox the phone kept from the last time it was fetched (Home's New
  // episodes reads it before the Podcasts tab has been opened).
  PodcastInboxCounts.setInbox(ShotPods.inbox);

  final home = ShotHomeController();
  Get.put<HomeScreenController>(home, permanent: true);
  home.quickPicks.value = QuickPicks(ShotData.songs(19, 31));
  home.homeChips.assignAll(const [
    HomeChip(title: 'Relax', params: 'relax'),
    HomeChip(title: 'Energize', params: 'energize'),
    HomeChip(title: 'Workout', params: 'workout'),
    HomeChip(title: 'Focus', params: 'focus'),
    HomeChip(title: 'Commute', params: 'commute'),
  ]);
  home.middleContent.assignAll(homeShelves());
  home.isContentFetched.value = true;

  // The rest of main.dart's services, real: they only read the (seeded)
  // preferences when made.
  Get.lazyPut(() => PipedServices(), fenix: true);
  Get.lazyPut(() => SponsorBlockService(), fenix: true);
  Get.lazyPut(() => SpotifyImportService(), fenix: true);
  Get.lazyPut(() => CloudMusicService(), fenix: true);
  Get.lazyPut(() => PluginService(), fenix: true);
  Get.lazyPut(() => SoulSyncService(), fenix: true);
  Get.lazyPut(() => SoulseekService(), fenix: true);
  Get.lazyPut(() => TrackAnalysisService(), fenix: true);
  Get.lazyPut(() => PlaylistMixService(), fenix: true);
  Get.lazyPut(() => VideoModeController(), fenix: true);
  Get.lazyPut(() => Downloader(), fenix: true);
  Get.lazyPut(() => PodcastQueueController(), fenix: true);
  Get.lazyPut(() => PodcastFolderController(), fenix: true);
  Get.lazyPut(() => AudiobookLibraryController(), fenix: true);

  Get.put<LibrarySongsController>(ShotLibrarySongsController(),
      permanent: true);
  Get.lazyPut<LibraryPlaylistsController>(() => LibraryPlaylistsController(),
      fenix: true);
  Get.lazyPut<LibraryAlbumsController>(() => LibraryAlbumsController(),
      fenix: true);
  Get.lazyPut<LibraryArtistsController>(() => LibraryArtistsController(),
      fenix: true);
  Get.lazyPut<LibraryPodcastsController>(() => ShotPodcastsController(),
      fenix: true);
  Get.put<AudiobookshelfService>(ShotAudiobookshelfService(), permanent: true);
}

/// The player's page colours for [items], as the app would take them from
/// their covers (it can't here: the covers are never downloaded).
void prefillCoverColors(Iterable<MediaItem> items) {
  for (final item in items) {
    final art = item.artUri?.toString() ?? '';
    if (art.isEmpty) continue;
    final (light, dark) = shotCoverColors(art);
    PlayerCoverColors.palettes[item.id] =
        coverPaletteFrom(dominant: dark, secondary: light);
    PodcastPlayerTint.colors[item.id] = podcastPlayerTint(dark);
  }
}

/// YouTube Music's Home feed: personal shelves (moved up into "Made for
/// you"), charts and mood shelves (merged), and plain editorial shelves.
List<Object> homeShelves() => [
      SongContent(title: 'Listen again', songs: ShotData.songs(39, 47)),
      // YouTube Music sends "Similar to" as the line over the artist's
      // name, with their photo.
      ArtistShelf(
          title: 'Nova Hart',
          header: ShelfHeader(
              strapline: 'Similar to',
              art: ShotData.artists.first.thumbnailUrl,
              round: true,
              named: true),
          artists: ShotData.artists.sublist(1, 9)),
      AlbumContent(
          title: 'New releases for you',
          albumList: ShotData.albums.sublist(0, 6)),
      SongContent(
          title: 'Today\'s Biggest Hits', songs: ShotData.songs(47, 57)),
      PlaylistContent(
          title: 'Chill evening',
          playlistList: ShotData.ytPlaylists.sublist(0, 5)),
      // YouTube Music's podcast shelves: episodes of shows you don't follow.
      SongContent(title: 'Popular episodes', songs: [
        for (final (i, (title, show)) in const [
          ('How Coffee Conquered the World', 'Curious Minds'),
          ('The Science of Sleep', 'Body Matters'),
          ('Inside the Tour de France Peloton', 'Long Ride Home'),
          ('Why Cities Grow the Way They Do', 'Urban Drift'),
          ('A Short History of the Bicycle', 'Curious Minds'),
        ].indexed)
          MediaItemBuilder.fromJson({
            'videoId': 'RiffYtEp${i}xxxx',
            'title': title,
            'artists': [
              {'name': show, 'id': null}
            ],
            'thumbnails': [
              {'url': ShotData.coverUrl('podcast $show'), 'width': 544}
            ],
            'length': '${38 + i * 7}:00',
            'duration': (38 + i * 7) * 60,
            'date': '${i + 2} days ago',
            'videoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
          }),
      ]),
      AlbumContent(
          title: 'Indie & alternative',
          albumList: ShotData.albums.sublist(6, 14)),
      PlaylistContent(
          title: 'Global sounds',
          playlistList: ShotData.ytPlaylists.sublist(5, 10)),
      SongContent(title: 'Music videos', songs: [
        for (final s in ShotData.songs(57, 65))
          s.copyWith(
              artUri: Uri.parse('https://i.ytimg.com/vi/${s.id}/hqdefault.jpg'))
      ]),
    ];
