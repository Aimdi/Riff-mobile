import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/artist.dart';
import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/music_service.dart';
import '/services/podcast_service.dart';
import '/ui/widgets/sort_widget.dart';
import '/utils/youtube_channel_url.dart';

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

  // Discover / directory search (YouTube Music podcasts + channels)
  final searchQuery = ''.obs;
  final searchResults = <Playlist>[].obs;
  /// YouTube channels found while searching (subscribe-as-podcast).
  final channelSearchResults = <Playlist>[].obs;
  final isSearching = false.obs;
  final hasSearched = false.obs;

  List<Playlist> tempListContainer = [];

  @override
  void onInit() {
    super.onInit();
    refreshLib().then((_) => loadSimilar());
    loadDiscovery();
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

  /// Search YTM podcasts and YouTube channels (Podcini-style subscribe).
  Future<void> searchPodcasts(String query) async {
    final term = query.trim();
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
          final artistRes =
              await ms.search(term, filter: 'artists', limit: 8);
          channels.addAll(_playlistsFromArtistSearch(artistRes));
        } catch (_) {}
      }

      searchResults.assignAll(list);
      channelSearchResults.assignAll(_uniqueById(channels));
    } catch (_) {
      searchResults.clear();
      channelSearchResults.clear();
    } finally {
      isSearching.value = false;
    }
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
      thumbnailUrl:
          thumb.isNotEmpty ? thumb : Playlist.thumbPlaceholderUrl,
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
    searchQuery.value = '';
    searchResults.clear();
    channelSearchResults.clear();
    hasSearched.value = false;
    isSearching.value = false;
  }

  Future<void> addToLibrary(Playlist podcast) async {
    final box = await Hive.openBox('LibraryPodcasts');
    final id = podcast.playlistId;
    final kind =
        podcast.kind == 'yt_channel' ? 'yt_channel' : 'podcast';
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
