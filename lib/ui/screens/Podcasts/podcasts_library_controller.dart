import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/artist.dart';
import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/music_service.dart';
import '/services/podcast_service.dart';
import '/services/youtube_podcast_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/sort_widget.dart';
import '/utils/youtube_channel_url.dart';

/// A YouTube Podcasts show as a library podcast. YouTube Music serves the
/// same show at `MPSP` + playlist id, so Follow, Inbox and the episode list
/// reuse the existing YouTube Music podcast paths.
Playlist ytShowAsPodcast(YtPodcastShow show) {
  final id = show.playlistId.startsWith('MPSP')
      ? show.playlistId
      : 'MPSP${show.playlistId}';
  final details = [
    show.author,
    if ((show.episodeCountText ?? '').isNotEmpty) show.episodeCountText!,
  ].where((e) => e.trim().isNotEmpty).join(' • ');
  return Playlist(
    title: show.title,
    playlistId: id,
    thumbnailUrl: show.thumbnailUrl.isNotEmpty
        ? show.thumbnailUrl
        : Playlist.thumbPlaceholderUrl,
    description: details.isEmpty ? 'Podcast' : details,
    kind: 'podcast',
  );
}

class LibraryPodcastsController extends GetxController {
  final libraryPodcasts = <Playlist>[].obs;
  final topEpisodes = <MediaItem>[].obs;
  final featuredPodcasts = <Playlist>[].obs;

  final isDiscoveryLoading = false.obs;
  final discoveryError = false.obs;
  final isContentFetched = false.obs;

  // "Popular with listeners of X" — similar podcasts to a random one you
  // follow, sourced from Apple's genre charts (see PodcastService.similar).
  final similarPodcasts = <Map<String, dynamic>>[].obs;
  final similarSeedTitle = ''.obs;
  final isSimilarLoading = false.obs;

  // YouTube Podcasts (WizeStream-style): YouTube's own podcast catalog.
  final ytPopularShows = <Playlist>[].obs;
  final ytPopularEpisodes = <MediaItem>[].obs;
  final isYtLoading = false.obs;

  bool get youtubePodcastsEnabled =>
      !Get.isRegistered<SettingsScreenController>() ||
      Get.find<SettingsScreenController>().youtubePodcastsEnabled.isTrue;

  // Discover / directory search (YouTube Music podcasts + channels)
  final searchQuery = ''.obs;
  final searchResults = <Playlist>[].obs;

  /// YouTube channels found while searching (subscribe-as-podcast).
  final channelSearchResults = <Playlist>[].obs;
  final isSearching = false.obs;
  final hasSearched = false.obs;

  List<Playlist> tempListContainer = [];

  // Inbox: merged latest episodes across every subscription (newest first,
  // played ones not yet filtered). Kept here, not in the Inbox widget, so
  // switching tabs doesn't refetch every feed.
  static const inboxMaxAge = Duration(minutes: 15);
  List<MediaItem>? inboxEpisodes;
  DateTime? inboxFetchedAt;

  /// Subscriptions the cached inbox was built from; a follow/unfollow
  /// invalidates it.
  String inboxSubsKey = '';

  /// Cached inbox when younger than [inboxMaxAge] and built from [subsKey].
  List<MediaItem>? freshInbox(String subsKey) {
    final at = inboxFetchedAt;
    if (inboxEpisodes == null || at == null || subsKey != inboxSubsKey) {
      return null;
    }
    if (DateTime.now().difference(at) > inboxMaxAge) return null;
    return inboxEpisodes;
  }

  void storeInbox(List<MediaItem> episodes, String subsKey) {
    inboxEpisodes = episodes;
    inboxSubsKey = subsKey;
    inboxFetchedAt = DateTime.now();
  }

  @override
  void onInit() {
    super.onInit();
    refreshLib().then((_) {
      loadSimilar();
      PodcastService.refreshMissingArtwork();
    });
    loadDiscovery();
    loadYoutubePodcasts();
  }

  /// Popular shows + popular episodes from YouTube's Podcasts page.
  Future<void> loadYoutubePodcasts({bool force = false}) async {
    if (!youtubePodcastsEnabled || isYtLoading.isTrue) return;
    if (!force && ytPopularShows.isNotEmpty) return;
    isYtLoading.value = true;
    try {
      final results = await Future.wait([
        YoutubePodcastService.popularShows()
            .catchError((_) => <YtPodcastShow>[]),
        YoutubePodcastService.popularEpisodes()
            .catchError((_) => <MediaItem>[]),
      ]);
      final shows = results[0] as List<YtPodcastShow>;
      ytPopularShows.assignAll(shows.take(30).map(ytShowAsPodcast));
      ytPopularEpisodes
          .assignAll((results[1] as List<MediaItem>).take(20).toList());
    } finally {
      isYtLoading.value = false;
    }
  }

  /// Load "similar podcasts" for a random subscription. Cheap & cached, so it
  /// runs on open and after the first subscription is added.
  Future<void> loadSimilar({bool force = false}) async {
    if (isSimilarLoading.isTrue) return;
    if (!force && similarPodcasts.isNotEmpty) return;
    final libs = libraryPodcasts.toList();
    if (libs.isEmpty) {
      similarPodcasts.clear();
      similarSeedTitle.value = '';
      return;
    }
    isSimilarLoading.value = true;
    try {
      final seed = libs[Random().nextInt(libs.length)];
      similarSeedTitle.value = seed.title;
      final res = await PodcastService.similar(seed.title);
      similarPodcasts.assignAll(res);
    } catch (_) {
      similarPodcasts.clear();
    } finally {
      isSimilarLoading.value = false;
    }
  }

  Future<void> refreshLib() async {
    final box = await Hive.openBox('LibraryPodcasts');
    libraryPodcasts.value = box.values
        .map<Playlist?>((item) {
          try {
            return Playlist.fromJson(item);
          } catch (_) {
            return null;
          }
        })
        .whereType<Playlist>()
        .toList();
    isContentFetched.value = true;
  }

  Future<void> loadDiscovery({bool force = false}) async {
    if (isDiscoveryLoading.isTrue) return;
    if (!force && (topEpisodes.isNotEmpty || featuredPodcasts.isNotEmpty)) {
      return;
    }
    isDiscoveryLoading.value = true;
    discoveryError.value = false;
    try {
      final data = await Get.find<MusicServices>().getPodcastDiscovery();
      topEpisodes
          .assignAll(List<MediaItem>.from(data['topEpisodes'] ?? const []));
      featuredPodcasts
          .assignAll(List<Playlist>.from(data['featuredPodcasts'] ?? const []));
    } catch (_) {
      discoveryError.value = true;
    } finally {
      isDiscoveryLoading.value = false;
    }
  }

  /// Bumped by every search and by [clearSearch]; only the newest search
  /// may write the results.
  int _searchGen = 0;

  /// Search YTM podcasts and YouTube channels (Podcini-style subscribe).
  Future<void> searchPodcasts(String query) async {
    final term = query.trim();
    final gen = ++_searchGen;
    searchQuery.value = term;
    if (term.isEmpty) {
      clearSearch();
      return;
    }
    isSearching.value = true;
    hasSearched.value = true;
    final ms = Get.find<MusicServices>();
    final list = <Playlist>[];
    final channels = <Playlist>[];
    try {
      // Paste a channel URL / UC… id → resolve directly.
      final channelId = YoutubeChannelUrl.tryChannelId(term);
      final handle = YoutubeChannelUrl.tryHandle(term);
      if (channelId != null) {
        try {
          final data = await ms.getChannelAsPodcast(channelId, limit: 1);
          channels.add(_channelPlaylistFromMap(data));
        } catch (_) {}
      } else if (handle != null) {
        try {
          final artistRes =
              await ms.search(handle, filter: 'artists', limit: 8);
          channels.addAll(_playlistsFromArtistSearch(artistRes));
        } catch (_) {}
      }

      final res = await ms.search(term, filter: 'podcasts', limit: 30);
      for (final entry in res.entries) {
        if (entry.key == 'params' || entry.key == 'searchEndpoint') continue;
        final val = entry.value;
        if (val is! List) continue;
        for (final item in val) {
          if (item is Playlist) {
            list.add(item.copyWith(kind: 'podcast'));
          }
        }
      }

      // Always surface channels as an extra row for YouTube-ish queries, and
      // lightly for normal queries so creators are discoverable.
      if (channels.isEmpty &&
          (YoutubeChannelUrl.looksLikeYoutubeInput(term) || term.length >= 3)) {
        try {
          final artistRes = await ms.search(term, filter: 'artists', limit: 8);
          channels.addAll(_playlistsFromArtistSearch(artistRes));
        } catch (_) {}
      }

      if (youtubePodcastsEnabled) {
        list.insertAll(0, await _youtubeShowsFor(term, channels));
      }
      // A newer search (or a cleared field) owns the results now.
      if (gen != _searchGen) return;
      searchResults.assignAll(_uniqueById(list));
      channelSearchResults.assignAll(_uniqueById(channels));
    } catch (_) {
      if (gen != _searchGen) return;
      searchResults.clear();
      channelSearchResults.clear();
    } finally {
      if (gen == _searchGen) isSearching.value = false;
    }
  }

  /// YouTube podcast search, plus the Podcasts tab of the first channels
  /// found (a creator's official shows rather than all their uploads).
  Future<List<Playlist>> _youtubeShowsFor(
      String term, List<Playlist> channels) async {
    final out = <Playlist>[];
    try {
      out.addAll(
          (await YoutubePodcastService.searchShows(term)).map(ytShowAsPodcast));
    } catch (_) {}
    for (final ch in channels.take(2)) {
      if (!ch.playlistId.startsWith('UC')) continue;
      try {
        out.addAll((await YoutubePodcastService.channelShows(ch.playlistId))
            .map(ytShowAsPodcast));
      } catch (_) {}
    }
    return out;
  }

  List<Playlist> _playlistsFromArtistSearch(Map res) {
    final out = <Playlist>[];
    for (final entry in res.entries) {
      if (entry.key == 'params' || entry.key == 'searchEndpoint') continue;
      final val = entry.value;
      if (val is! List) continue;
      for (final item in val) {
        if (item is Artist) {
          final id = _normalizeChannelId(item.browseId);
          if (id.isEmpty) continue;
          out.add(Playlist(
            title: item.name,
            playlistId: id,
            thumbnailUrl: item.thumbnailUrl,
            description: item.subscribers ?? 'YouTube channel',
            kind: 'yt_channel',
          ));
        }
      }
    }
    return out;
  }

  /// Strip MPLA prefix / keep bare UC… ids for library keys.
  String _normalizeChannelId(String raw) {
    var id = raw.trim();
    if (id.startsWith('MPLA')) id = id.substring(4);
    return id;
  }

  Playlist _channelPlaylistFromMap(Map<String, dynamic> data) {
    final thumbs = data['thumbnails'];
    final thumb = Thumbnail.bestUrl(thumbs, target: 'extraHigh');
    final id = _normalizeChannelId('${data['playlistId'] ?? ''}');
    return Playlist(
      title: '${data['title'] ?? ''}',
      playlistId: id,
      thumbnailUrl: thumb.isNotEmpty ? thumb : Playlist.thumbPlaceholderUrl,
      description: '${data['description'] ?? 'YouTube channel'}',
      kind: 'yt_channel',
    );
  }

  List<Playlist> _uniqueById(List<Playlist> list) {
    final seen = <String>{};
    final out = <Playlist>[];
    for (final p in list) {
      if (p.playlistId.isEmpty || !seen.add(p.playlistId)) continue;
      out.add(p);
    }
    return out;
  }

  /// Entering the search field shows the "browse" state (a suggestions grid)
  /// even before a query is typed — AntennaPod's add-podcast behaviour.
  void enterSearchMode() {
    hasSearched.value = true;
    if (featuredPodcasts.isEmpty) loadDiscovery();
  }

  void clearSearch() {
    _searchGen++;
    searchQuery.value = '';
    searchResults.clear();
    channelSearchResults.clear();
    hasSearched.value = false;
    isSearching.value = false;
  }

  Future<void> addToLibrary(Playlist podcast) async {
    final box = await Hive.openBox('LibraryPodcasts');
    final id = podcast.playlistId;
    final kind = podcast.kind == 'yt_channel' ? 'yt_channel' : 'podcast';
    final toStore = podcast.copyWith(kind: kind);
    await box.put(id, {
      ...toStore.toJson(),
      'kind': kind,
      'description': podcast.description ??
          (kind == 'yt_channel' ? 'YouTube channel' : 'Podcast'),
    });
    await refreshLib();
    // Seed the "similar" row once we have something to base it on.
    if (similarPodcasts.isEmpty) loadSimilar();
  }

  /// Subscribe to a YouTube channel as a podcast (videos = episodes).
  ///
  /// [seed] is used when the channel fetch fails so Follow still works from
  /// search results (episodes load later when the channel is opened).
  Future<Playlist?> subscribeYoutubeChannel(String channelId,
      {Playlist? seed}) async {
    final id = _normalizeChannelId(
        channelId.isNotEmpty ? channelId : (seed?.playlistId ?? ''));
    if (id.isEmpty) return null;
    try {
      final data =
          await Get.find<MusicServices>().getChannelAsPodcast(id, limit: 1);
      final pl = _channelPlaylistFromMap(data);
      if (pl.playlistId.isNotEmpty && pl.title.isNotEmpty) {
        await addToLibrary(pl);
        return pl;
      }
    } catch (_) {}
    if (seed != null) {
      final toStore = Playlist(
        title: seed.title.isNotEmpty ? seed.title : id,
        playlistId: id,
        thumbnailUrl: seed.thumbnailUrl,
        description: seed.description ?? 'YouTube channel',
        kind: 'yt_channel',
      );
      await addToLibrary(toStore);
      return toStore;
    }
    return null;
  }

  Future<void> removeFromLibrary(String playlistId) async {
    final box = await Hive.openBox('LibraryPodcasts');
    await box.delete(playlistId);
    await refreshLib();
    if (libraryPodcasts.isEmpty) {
      similarPodcasts.clear();
      similarSeedTitle.value = '';
    }
  }

  bool isInLibrary(String playlistId) {
    return libraryPodcasts.any((p) => p.playlistId == playlistId);
  }

  void onSort(SortType sortType, bool isAscending) {
    final list = libraryPodcasts.toList();
    switch (sortType) {
      case SortType.Name:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      default:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    if (!isAscending) {
      libraryPodcasts.value = list.reversed.toList();
    } else {
      libraryPodcasts.value = list;
    }
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryPodcasts.toList();
  }

  void onSearch(String value, String? tag) {
    libraryPodcasts.value = tempListContainer
        .where((e) => e.title.toLowerCase().contains(value.toLowerCase()))
        .toList();
  }

  void onSearchClose(String? tag) {
    libraryPodcasts.value = tempListContainer.toList();
    tempListContainer.clear();
  }
}

/// Runs [task] over [items] with at most [concurrency] in flight, returning
/// results in input order. Used by the Inbox so dozens of feeds don't all
/// hit the network (and the parser) at once.
Future<List<R>> mapWithConcurrency<T, R>(
    List<T> items, int concurrency, Future<R> Function(T item) task) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await task(items[i]);
    }
  }

  final workers = concurrency < 1 ? 1 : concurrency;
  await Future.wait(List.generate(
      workers < items.length ? workers : items.length, (_) => worker()));
  return results.cast<R>();
}
