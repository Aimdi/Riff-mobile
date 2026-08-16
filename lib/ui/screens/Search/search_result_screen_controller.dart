import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/helper.dart';
import '../Home/home_screen_controller.dart';
import '/services/music_service.dart';
import '/services/plugin_service.dart';
import '/ui/player/play_queue_order.dart';
import '/ui/widgets/sort_widget.dart';

class SearchResultScreenController extends GetxController
    with GetTickerProviderStateMixin {
  final navigationRailCurrentIndex = 0.obs;
  final isResultContentFetced = false.obs;
  final isSeparatedResultContentFetced = false.obs;
  final resultContent = <String, dynamic>{}.obs;
  final separatedResultContent = <String, dynamic>{}.obs;
  final musicServices = Get.find<MusicServices>();
  final queryString = ''.obs;
  final railItems = <String>[].obs;
  final railitemHeight = Get.size.height.obs;
  final additionalParamNext = {};
  bool continuationInProgress = false;
  TabController? tabController;
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
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onReady();
  }

  Future<void> onDestinationSelected(int value,
      {bool ignoreTabCommand = false}) async {
    if (railItems.isEmpty) {
      return;
    }

    isTabTransitionReversed = value > navigationRailCurrentIndex.value;

    isSeparatedResultContentFetced.value = false;
    navigationRailCurrentIndex.value = value;

    if (tabController != null && !ignoreTabCommand) {
      tabController?.animateTo(value);
    }

    if (value > 0) {
      final tabName = railItems[value - 1];
      // Soulseek is in-app plugin search — never hit YTM filters.
      if (isSoulseekRail(tabName)) {
        isSeparatedResultContentFetced.value = true;
        return;
      }
      if (!separatedResultContent.containsKey(tabName) ||
          separatedResultContent[tabName].isEmpty) {
        final itemCount = (tabName == 'Songs' ||
                tabName == 'Videos' ||
                tabName == 'Episodes')
            ? 25
            : 10;
        try {
          final endpoints = (resultContent['searchEndpoint'] as Map?)
                  ?.cast<String, dynamic>() ??
              {};
          final x = await musicServices.search(queryString.value,
              filter: tabName.replaceAll(' ', '_').toLowerCase(),
              limit: itemCount,
              filterParams: endpoints[tabName]);
          separatedResultContent[tabName] =
              _listFromSearchResponse(x, tabName);
          additionalParamNext[tabName] = x['params'];
          isSeparatedResultContentFetced.value = true;
          final scrollController = scrollControllers[tabName];
          scrollController?.addListener(() {
            if (scrollController.hasClients == false) return;
            double maxScroll = scrollController.position.maxScrollExtent;
            double currentScroll = scrollController.position.pixels;
            final next = additionalParamNext[tabName];
            if (next is! Map) return;
            if (currentScroll >= maxScroll / 2 &&
                next['additionalParams'] !=
                    '&ctoken=null&continuation=null') {
              if (!continuationInProgress) {
                printINFO("Acchhsk");
                continuationInProgress = true;
                getContinuationContents();
              }
            }
          });
        } catch (e) {
          printERROR('Search filter "$tabName" failed: $e');
          separatedResultContent[tabName] =
              searchTabFallback(overview: resultContent[tabName]);
          isSeparatedResultContentFetced.value = true;
        }
      }
    }
    isSeparatedResultContentFetced.value = true;
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
        _initDesktopTabsIfNeeded();
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

      final len =
          railItems.where((element) => element.contains('playlists')).length;
      final calH = 30 + (railItems.length + 1 - len) * 123 + len * 150.0;
      railitemHeight.value =
          calH >= railitemHeight.value ? calH : railitemHeight.value;

      for (String item in railItems) {
        scrollControllers.putIfAbsent(item, () => ScrollController());
      }

      if (GetPlatform.isDesktop) {
        for (var element in railItems) {
          separatedResultContent[element] = [];
        }

        tabController =
            TabController(length: railItems.length + 1, vsync: this);

        tabController?.animation?.addListener(() {
          int indexChange = tabController!.offset.round();
          int index = tabController!.index + indexChange;

          if (index != navigationRailCurrentIndex.value) {
            onDestinationSelected(index, ignoreTabCommand: true);
          }
        });
      }
      isResultContentFetced.value = true;
    }
  }

  void _initDesktopTabsIfNeeded() {
    if (!GetPlatform.isDesktop) {
      return;
    }
    for (var element in railItems) {
      if (!isSoulseekRail(element)) {
        separatedResultContent.putIfAbsent(element, () => []);
      }
    }

    tabController?.dispose();
    tabController = TabController(length: railItems.length + 1, vsync: this);

    tabController?.animation?.addListener(() {
      int indexChange = tabController!.offset.round();
      int index = tabController!.index + indexChange;

      if (index != navigationRailCurrentIndex.value) {
        onDestinationSelected(index, ignoreTabCommand: true);
      }
    });
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
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    tabController?.dispose();
    super.onClose();
  }
}
