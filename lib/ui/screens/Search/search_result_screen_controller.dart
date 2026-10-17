import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/helper.dart';
import '/services/music_service.dart';
import '/services/plugin_service.dart';
import '/services/search_spelling.dart';
import '/services/search_top_result.dart';
import '/ui/player/play_queue_order.dart';
import '/ui/widgets/sort_widget.dart';

class SearchResultScreenController extends GetxController {
  final navigationRailCurrentIndex = 0.obs;
  final isResultContentFetced = false.obs;
  final isSeparatedResultContentFetced = false.obs;
  final resultContent = <String, dynamic>{}.obs;
  final separatedResultContent = <String, dynamic>{}.obs;
  final musicServices = Get.find<MusicServices>();
  final queryString = ''.obs;
  final railItems = <String>[].obs;
  final additionalParamNext = {};
  bool continuationInProgress = false;
  bool isTabTransitionReversed = false;
  //ScrollContollers List
  final Map<String, ScrollController> scrollControllers = {};

  /// Extra Home-search sidebar destination (not a YouTube Music filter).
  static const soulseekRailItem = 'Soulseek';

  static const preferredRailOrder = [
    'Songs',
    'Videos',
    'Albums',
    'Artists',
    'Community playlists',
    'Featured playlists',
    'Podcasts',
    'Episodes',
  ];

  bool get soulseekAvailable =>
      Get.isRegistered<PluginService>() &&
      Get.find<PluginService>().isInstalled(PluginIds.seeker);

  bool isSoulseekRail(String? name) => name == soulseekRailItem;

  void _ensureSoulseekRail() {
    if (!soulseekAvailable) return;
    if (!railItems.contains(soulseekRailItem)) {
      railItems.add(soulseekRailItem);
    }
    scrollControllers.putIfAbsent(
        soulseekRailItem, () => ScrollController());
  }

  @override
  void onReady() {
    _getInitSearchResult();
    super.onReady();
  }

  /// First-page loads in flight, by tab: going back to a tab that is still
  /// loading waits for that request instead of sending another.
  final Map<String, Future<void>> _tabLoads = {};

  /// Tabs whose scroll controller already pages in more results.
  final Set<String> _pagedTabs = {};

  /// The words searched exactly as typed ("Search instead for …"):
  /// YouTube Music leaves their spelling alone, in every tab too.
  bool _exact = false;
  String? _exactParams;

  /// Bumped for each new search: a tab still loading for the one before
  /// doesn't put its results under this one.
  int _searchGen = 0;

  Future<void> onDestinationSelected(int value) async {
    if (railItems.isEmpty) {
      return;
    }

    isTabTransitionReversed = value > navigationRailCurrentIndex.value;

    isSeparatedResultContentFetced.value = false;
    navigationRailCurrentIndex.value = value;

    if (value > 0) {
      final tabName = railItems[value - 1];
      // Soulseek is in-app plugin search — never hit YTM filters.
      if (isSoulseekRail(tabName)) {
        isSeparatedResultContentFetced.value = true;
        return;
      }
      if (!separatedResultContent.containsKey(tabName) ||
          separatedResultContent[tabName].isEmpty) {
        // Block body: `=> _tabLoads.remove(..)` would hand whenComplete
        // this very future to wait on, and it would never complete. Only
        // its own entry: one for other words may have taken its place.
        late final Future<void> load;
        load = _tabLoads[tabName] ??= _loadTab(tabName).whenComplete(() {
          if (identical(_tabLoads[tabName], load)) _tabLoads.remove(tabName);
        });
        await load;
      }
    }
    // A slower load for a tab the user has already left must not mark the
    // tab now on screen as loaded: its list isn't there yet, and the list
    // widget would be handed null.
    if (!isClosed && navigationRailCurrentIndex.value == value) {
      isSeparatedResultContentFetced.value = true;
    }
  }

  /// Fetches the first page of [tabName] (or falls back to the overview's
  /// items) and starts paging it on scroll.
  Future<void> _loadTab(String tabName) async {
    final itemCount =
        (tabName == 'Songs' || tabName == 'Videos' || tabName == 'Episodes')
            ? 25
            : 10;
    final gen = _searchGen;
    try {
      final endpoints =
          (resultContent['searchEndpoint'] as Map?)?.cast<String, dynamic>() ??
              {};
      final x = await musicServices.search(queryString.value,
          filter: tabName.replaceAll(' ', '_').toLowerCase(),
          limit: itemCount,
          // Searched as typed: Riff's own filter, spelling left alone.
          filterParams: _exact ? null : endpoints[tabName],
          ignoreSpelling: _exact);
      if (isClosed || gen != _searchGen) return;
      separatedResultContent[tabName] = _listFromSearchResponse(x, tabName);
      additionalParamNext[tabName] = x['params'];
      _pageOnScroll(tabName);
    } catch (e) {
      printERROR('Search filter "$tabName" failed: $e');
      if (isClosed || gen != _searchGen) return;
      separatedResultContent[tabName] =
          searchTabFallback(overview: resultContent[tabName]);
    }
  }

  /// Loads the next page of [tabName] once its list is scrolled halfway.
  /// Added once per tab (a tab reloaded after an empty first page used to
  /// stack another listener each time).
  void _pageOnScroll(String tabName) {
    final scrollController = scrollControllers[tabName];
    if (scrollController == null || !_pagedTabs.add(tabName)) return;
    scrollController.addListener(() {
      if (scrollController.hasClients == false) return;
      double maxScroll = scrollController.position.maxScrollExtent;
      double currentScroll = scrollController.position.pixels;
      final next = additionalParamNext[tabName];
      if (next is! Map) return;
      if (currentScroll >= maxScroll / 2 &&
          next['additionalParams'] != '&ctoken=null&continuation=null') {
        if (!continuationInProgress) {
          continuationInProgress = true;
          getContinuationContents();
        }
      }
    });
  }

  List _listFromSearchResponse(Map<String, dynamic> x, String tabName) {
    final direct = x[tabName];
    if (direct is List) return List.from(direct);
    for (final entry in x.entries) {
      if (entry.key == 'params' || entry.key == 'searchEndpoint') continue;
      if (entry.value is List) return List.from(entry.value as List);
    }
    return [];
  }

  Future<void> getContinuationContents() async {
    final idx = navigationRailCurrentIndex.value - 1;
    if (idx < 0 || idx >= railItems.length) {
      continuationInProgress = false;
      return;
    }
    final tabName = railItems[idx];
    if (isSoulseekRail(tabName)) {
      continuationInProgress = false;
      return;
    }
    try {
      final next = additionalParamNext[tabName];
      if (next is! Map) {
        continuationInProgress = false;
        return;
      }
      final x = await musicServices.getSearchContinuation(next);
      final more = _listFromSearchResponse(x, tabName);
      (separatedResultContent[tabName] as List?)?.addAll(more);
      additionalParamNext[tabName] = x['params'];
      separatedResultContent.refresh();
    } catch (e) {
      printERROR('Search continuation failed: $e');
    } finally {
      continuationInProgress = false;
    }
  }

  void viewAllCallback(String text) {
    if (isSoulseekRail(text)) return;
    onDestinationSelected(railItems.indexOf(text) + 1);
  }

  /// The search itself failed (offline, YouTube Music out of reach), not
  /// that it found nothing: the page says so and offers to try again, as
  /// Spotify's and YouTube Music's do.
  final searchFailed = false.obs;

  /// Searches the same words again, after [searchFailed].
  Future<void> retrySearch() => _search(queryString.value);

  /// YouTube Music's best match for this search ("Top result"), if any.
  Object? get topResult => resultContent[SearchTopResult.key];

  /// YouTube Music's spelling help for this search, if it gave any.
  SearchSpelling? get spelling {
    final s = resultContent[SearchSpelling.key];
    return s is SearchSpelling ? s : null;
  }

  /// "Did you mean …": its words searched instead.
  Future<void> searchCorrected() async {
    final s = spelling;
    if (s == null) return;
    await _searchInstead(s.corrected);
  }

  /// "Search instead for …": the words as typed, searched exactly.
  Future<void> searchOriginal() async {
    final s = spelling;
    if (s == null) return;
    await _searchInstead(s.original ?? queryString.value,
        exact: true, params: s.originalParams);
  }

  /// [query] searched in place of the one on screen, from All.
  Future<void> _searchInstead(String query,
      {bool exact = false, String? params}) async {
    _exact = exact;
    _exactParams = params;
    _searchGen++;
    _tabLoads.clear();
    separatedResultContent.clear();
    additionalParamNext.clear();
    navigationRailCurrentIndex.value = 0;
    await _search(query);
  }

  Future<void> _getInitSearchResult() async {
    final args = Get.arguments;
    if (args != null) await _search(args);
  }

  Future<void> _search(String query) async {
    isResultContentFetced.value = false;
    searchFailed.value = false;
    queryString.value = query;
    try {
      resultContent.value = await musicServices.search(query,
          ignoreSpelling: _exact && _exactParams == null,
          filterParams: _exact ? _exactParams : null);
    } catch (e) {
      printERROR('Search failed: $e');
      resultContent.value = {};
      railItems.clear();
      _ensureSoulseekRail();
      searchFailed.value = true;
      isResultContentFetced.value = true;
      return;
    }

    final endpoints =
        (resultContent['searchEndpoint'] as Map?)?.cast<String, dynamic>() ??
            {};
    final available = <String>{};
    for (final key in preferredRailOrder) {
      if (resultContent.containsKey(key) || endpoints.containsKey(key)) {
        available.add(key);
        resultContent.putIfAbsent(key, () => []);
      }
    }
    // Preserve any unexpected but useful keys from the response.
    for (final key in resultContent.keys) {
      if (key == 'searchEndpoint' || key == 'params') continue;
      if (preferredRailOrder.contains(key)) continue;
      if (isSoulseekRail(key)) continue;
      if (resultContent[key] is List &&
          (resultContent[key] as List).isNotEmpty) {
        available.add(key);
      }
    }

    railItems.value = [
      ...preferredRailOrder.where(available.contains),
      ...available.where((k) => !preferredRailOrder.contains(k)),
    ];
    _ensureSoulseekRail();

    for (String item in railItems) {
      scrollControllers.putIfAbsent(item, () => ScrollController());
    }
    isResultContentFetced.value = true;
  }

  void onSort(SortType sortType, bool isAscending, String title) {
    if (isSoulseekRail(title)) return;
    if (title == 'Songs' || title == 'Videos' || title == 'Episodes') {
      final songList = separatedResultContent[title].toList();
      sortSongsNVideos(songList, sortType, isAscending);
      separatedResultContent[title] = songList;
    } else if (title.contains('playlists') || title == 'Podcasts') {
      final playlists = separatedResultContent[title].toList();
      sortPlayLists(playlists, sortType, isAscending);
      separatedResultContent[title] = playlists;
    } else if (title == 'Artists') {
      final artistList = separatedResultContent[title].toList();
      sortArtist(artistList, sortType, isAscending);
      separatedResultContent[title] = artistList;
    } else if (title == 'Albums') {
      final albumList = separatedResultContent[title].toList();
      sortAlbumNSingles(albumList, sortType, isAscending);
      separatedResultContent[title] = albumList;
    }
  }

  @override
  void onClose() {
    for (String item in railItems) {
      scrollControllers[item]?.dispose();
    }
    super.onClose();
  }
}
