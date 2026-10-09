import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/helper.dart';
import '/services/music_service.dart';
import '/services/plugin_service.dart';
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
        // this very future to wait on, and it would never complete.
        await (_tabLoads[tabName] ??= _loadTab(tabName).whenComplete(() {
          _tabLoads.remove(tabName);
        }));
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
    try {
      final endpoints =
          (resultContent['searchEndpoint'] as Map?)?.cast<String, dynamic>() ??
              {};
      final x = await musicServices.search(queryString.value,
          filter: tabName.replaceAll(' ', '_').toLowerCase(),
          limit: itemCount,
          filterParams: endpoints[tabName]);
      if (isClosed) return;
      separatedResultContent[tabName] = _listFromSearchResponse(x, tabName);
      additionalParamNext[tabName] = x['params'];
      _pageOnScroll(tabName);
    } catch (e) {
      printERROR('Search filter "$tabName" failed: $e');
      if (isClosed) return;
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

  Future<void> _getInitSearchResult() async {
    isResultContentFetced.value = false;
    final args = Get.arguments;
    if (args != null) {
      queryString.value = args;
      try {
        resultContent.value = await musicServices.search(args);
      } catch (e) {
        printERROR('Search failed: $e');
        resultContent.value = {};
        railItems.clear();
        _ensureSoulseekRail();
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
