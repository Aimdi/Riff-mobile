import '/models/home_chip.dart';
import '/models/artist.dart';
import '/models/home_shelf_content.dart';
import '/services/crash_report.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/services/ban_service.dart';
import '/models/quick_picks.dart';
import '/services/music_service.dart';
import '/utils/content_filters.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/widgets/new_version_dialog.dart';

/// Side-rail tab indices ([HomeScreenController.tabIndex]), in rail order.
/// Playlists / Albums / Artists sit under Songs on the phone rail.
abstract final class RailTab {
  static const home = 0;

  /// Search field and the Explore feed, right under Home.
  static const discover = 1;
  static const songs = 2;
  static const podcasts = 3;
  static const audiobooks = 4;
  static const playlists = 5;
  static const albums = 6;
  static const artists = 7;
  static const settings = 8;
}

class HomeScreenController extends GetxController {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;

  /// Cached Home is on screen because a background refresh failed.
  final showingCachedWhileOffline = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;
  final showVersionDialog = true.obs;

  /// YouTube Music's own home chips ("Relax", "Workout", …).
  final homeChips = <HomeChip>[].obs;

  /// The chip the feed is filtered by; null for the plain feed.
  final selectedChip = Rxn<HomeChip>();

  /// Shelves YouTube Music returned for [selectedChip].
  final chipContent = [].obs;
  final chipLoading = false.obs;
  final chipError = false.obs;

  /// Stable horizontal shelf scroll controllers keyed by section id.
  /// Creating/disposing these inside Obx builders was a Home jank source.
  final Map<String, ScrollController> _contentScrollControllers = {};
  bool reverseAnimationtransiton = false;

  ScrollController scrollControllerFor(String key) {
    return _contentScrollControllers.putIfAbsent(key, ScrollController.new);
  }

  @override
  onInit() {
    super.onInit();
    loadContent();
    if (updateCheckFlag) _checkNewVersion();
    Future.delayed(const Duration(seconds: 4), () {
      CrashReport.checkAndOffer(
          Get.find<SettingsScreenController>().currentVersion);
    });
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    if (isCachedHomeScreenDataEnabled) {
      final loaded = await loadContentFromDb();

      if (loaded) {
        final currTimeSecsDiff = DateTime.now().millisecondsSinceEpoch -
            (box.get("homeScreenDataTime") ??
                DateTime.now().millisecondsSinceEpoch);
        if (currTimeSecsDiff / 1000 > 3600 * 8) {
          loadContentFromNetwork(silent: true);
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
  }

  Future<bool> loadContentFromDb() async {
    // Prefer the already-open box from initHiveCritical (avoids a mid-frame
    // open on the UI isolate during Home first paint).
    final homeScreenData = Hive.isBoxOpen("homeScreenData")
        ? Hive.box("homeScreenData")
        : await Hive.openBox("homeScreenData");
    try {
      return _applyCachedHome(homeScreenData);
    } catch (e) {
      // A bad cached payload (older format, partial write) must not leave
      // the Home shimmer up forever: drop it and let the caller refetch.
      printERROR("Cached home data unreadable, refetching: $e");
      try {
        await homeScreenData.clear();
      } catch (_) {}
      return false;
    }
  }

  bool _applyCachedHome(Box homeScreenData) {
    if (homeScreenData.keys.isNotEmpty) {
      final String quickPicksType = homeScreenData.get("quickPicksType");
      final List quickPicksData = homeScreenData.get("quickPicks");
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      _setQuickPicks(
          quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
          title: quickPicksType);
      middleContent.value = middleContentData.map(_shelfFromJson).toList();
      fixedContent.value = fixedContentData.map(_shelfFromJson).toList();
      final chipData = homeScreenData.get("homeChips");
      if (chipData is List) {
        homeChips.assignAll(chipData
            .whereType<Map>()
            .map(HomeChip.fromJson)
            .where((c) => c.params.isNotEmpty));
      }
      isContentFetched.value = true;
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  List<MediaItem> _filterSongs(List<MediaItem> songs) {
    final s = Get.find<SettingsScreenController>();
    return ContentFilters.apply(
      songs,
      hideVideos: s.hideVideoSongs.isTrue,
      hideShorts: s.hideShorts.isTrue,
    );
  }

  void _setQuickPicks(List<MediaItem> songs, {required String title}) {
    quickPicks.value = QuickPicks(_filterSongs(songs), title: title);
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    final box = Hive.box("AppPrefs");
    String contentType = box.get("discoverContentType") ?? "QP";

    networkError.value = false;
    if (!silent) showingCachedWhileOffline.value = false;
    // Tracks whether *this* fetch produced Quick Picks. Checking
    // quickPicks.songList.isEmpty instead never refreshed them on a silent
    // refresh (already filled from cache) and re-saved the stale list.
    var quickPicksSet = false;
    try {
      List middleContentTemp = [];
      final homeContentListMap = await _musicServices.getHome(
          limit:
              Get.find<SettingsScreenController>().noOfHomeScreenContent.value);
      if (contentType == "TR") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Trending");
        if (index != -1 && index != 0) {
          _setQuickPicks(
              List<MediaItem>.from(homeContentListMap[index]["contents"]),
              title: "Trending");
          quickPicksSet = true;
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            _setQuickPicks(List<MediaItem>.from(charts[index]["contents"]),
                title: charts[index]['title']);
            quickPicksSet = true;
            middleContentTemp.addAll(charts);
          }
        }
      } else if (contentType == "TMV") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Top music videos");
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          _setQuickPicks(List<MediaItem>.from(con["contents"]),
              title: con["title"]);
          quickPicksSet = true;
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            _setQuickPicks(List<MediaItem>.from(charts[index]["contents"]),
                title: charts[index]["title"]);
            quickPicksSet = true;
            middleContentTemp.addAll(charts);
          }
        }
      } else if (contentType == "BOLI") {
        try {
          final songId = box.get("recentSongId");
          if (songId != null) {
            final rel = (await _musicServices.getContentRelatedToSong(
                songId, getContentHlCode()));
            final con = rel.removeAt(0);
            quickPicks.value =
                QuickPicks(List<MediaItem>.from(con["contents"]));
            quickPicksSet = true;
            middleContentTemp.addAll(rel);
          }
        } catch (e) {
          printERROR(
              "Seems Based on last interaction content currently not available!");
        }
      }

      if (!quickPicksSet) {
        // YT Music renames/reorders home sections over time; fall back to
        // the first song section instead of crashing on a missing title.
        int index = homeContentListMap
            .indexWhere((element) => element['title'] == "Quick picks");
        if (index == -1) {
          index = homeContentListMap.indexWhere((element) =>
              (element["contents"] as List).isNotEmpty &&
              element["contents"][0] is MediaItem);
        }
        if (index != -1) {
          final con = homeContentListMap.removeAt(index);
          _setQuickPicks(List<MediaItem>.from(con["contents"]),
              title: con["title"] ?? "Quick picks");
          quickPicksSet = true;
        }
      }

      middleContent.value = _setContentList(middleContentTemp);
      fixedContent.value = _setContentList(homeContentListMap);
      _takeChips();

      isContentFetched.value = true;
      showingCachedWhileOffline.value = false;

      // set home content last update time
      cachedHomeScreenData(updateAll: true);
      await Hive.box("AppPrefs")
          .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
      // ignore: unused_catch_stack
    } on NetworkError catch (r, e) {
      printERROR("Home Content not loaded due to ${r.message}");
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
      if (silent && isContentFetched.isTrue) {
        showingCachedWhileOffline.value = true;
      }
    } catch (e, stack) {
      // A parsing failure (YT Music response shape change) must surface
      // the retry UI instead of leaving the loading shimmer forever.
      printERROR("Home Content failed to parse: $e\n$stack");
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
      if (silent && isContentFetched.isTrue) {
        showingCachedWhileOffline.value = true;
      }
    }
  }

  /// Filter the feed by [chip]; tapping the selected chip again (or
  /// passing null) goes back to the plain feed. A late reply for a chip the
  /// user has already left is dropped.
  Future<void> selectChip(HomeChip? chip) async {
    if (chip == null || chip == selectedChip.value) {
      selectedChip.value = null;
      chipContent.clear();
      chipError.value = false;
      return;
    }
    selectedChip.value = chip;
    chipContent.clear();
    chipError.value = false;
    chipLoading.value = true;
    try {
      final sections = await _musicServices.getHome(
          limit:
              Get.find<SettingsScreenController>().noOfHomeScreenContent.value,
          params: chip.params);
      if (selectedChip.value != chip) return;
      chipContent.value = _setContentList(List.of(sections as List));
      chipError.value = chipContent.isEmpty;
    } catch (e) {
      printERROR("Home chip ${chip.title} failed: $e");
      if (selectedChip.value == chip) chipError.value = true;
    } finally {
      if (selectedChip.value == chip) chipLoading.value = false;
    }
  }

  void _takeChips() {
    final chips = _musicServices.lastHomeChips;
    if (chips.isNotEmpty) homeChips.assignAll(chips);
  }

  List _setContentList(
    List<dynamic> contents,
  ) {
    List contentTemp = [];
    for (var content in contents) {
      if ((content["contents"]).isEmpty) continue;
      if ((content["contents"][0]).runtimeType == Playlist) {
        final tmp = PlaylistContent(
            playlistList: BanService.filterCollections(
                (content["contents"]).whereType<Playlist>().toList()),
            title: content["title"]);
        if (tmp.playlistList.length >= 2) {
          contentTemp.add(tmp);
        }
      } else if ((content["contents"][0]).runtimeType == Album) {
        final tmp = AlbumContent(
            albumList: BanService.filterCollections(
                (content["contents"]).whereType<Album>().toList()),
            title: content["title"]);
        if (tmp.albumList.length >= 2) {
          contentTemp.add(tmp);
        }
      } else if (content["contents"][0] is MediaItem) {
        // "Listen again", "Forgotten favourites", … used to be dropped
        // here, which left Home with almost nothing to scroll.
        final songs = _filterSongs(BanService.filterTracks(
                (content["contents"]).whereType<MediaItem>().toList())
            .whereType<MediaItem>()
            .toList());
        final title = '${content["title"] ?? ''}';
        if (songs.length >= 4 && title.isNotEmpty) {
          contentTemp.add(SongContent(title: title, songs: songs));
        }
      } else if (content["contents"][0] is Artist) {
        final artists = (content["contents"]).whereType<Artist>().toList();
        final title = '${content["title"] ?? ''}';
        if (artists.length >= 2 && title.isNotEmpty) {
          contentTemp.add(ArtistShelf(title: title, artists: artists));
        }
      }
    }
    return contentTemp;
  }

  static dynamic _shelfFromJson(dynamic e) {
    switch (e["type"]) {
      case "Album Content":
        return AlbumContent.fromJson(e);
      case "Song Content":
        return SongContent.fromJson(e);
      case "Artist Content":
        return ArtistShelf.fromJson(e);
      default:
        return PlaylistContent.fromJson(e);
    }
  }

  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == 'QP') {
      final homeContentListMap = await _musicServices.getHome(limit: 3);
      quickPicks_ = QuickPicks(
          List<MediaItem>.from(homeContentListMap[0]["contents"]),
          title: homeContentListMap[0]["title"]);
    } else if (val == "TMV" || val == 'TR') {
      try {
        final charts = await _musicServices.getCharts(val);
        final index = charts.indexWhere((element) =>
            element['title'] ==
            (val == "TMV" ? "Top Music Videos" : "Trending"));
        quickPicks_ = QuickPicks(
            List<MediaItem>.from(charts[index]["contents"]),
            title: charts[index]["title"]);
      } catch (e) {
        printERROR(
            "Seems ${val == "TMV" ? "Top music videos" : "Trending songs"} currently not available!");
      }
    } else {
      songId ??= Hive.box("AppPrefs").get("recentSongId");
      if (songId != null) {
        try {
          final value = await _musicServices.getContentRelatedToSong(
              songId, getContentHlCode());
          middleContent.value = _setContentList(value);
          if (value.isNotEmpty && (value[0]['title']).contains("like")) {
            quickPicks_ =
                QuickPicks(List<MediaItem>.from(value[0]["contents"]));
            Hive.box("AppPrefs").put("recentSongId", songId);
          }
          // ignore: empty_catches
        } catch (e) {}
      }
    }
    if (quickPicks_ == null) return;

    _setQuickPicks(quickPicks_.songList, title: quickPicks_.title);

    // set home content last update time
    cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await Hive.box("AppPrefs")
        .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId =
        Get.find<SettingsScreenController>().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void _checkNewVersion() {
    showVersionDialog.value =
        Hive.box("AppPrefs").get("newVersionVisibility") ?? true;
    if (showVersionDialog.isTrue) {
      newVersionCheck(Get.find<SettingsScreenController>().currentVersion)
          .then((value) {
        if (value) {
          showDialog(
              context: Get.context!,
              builder: (context) => const NewVersionDialog());
        }
      });
    }
  }

  void onChangeVersionVisibility(bool val) {
    Hive.box("AppPrefs").put("newVersionVisibility", !val);
    showVersionDialog.value = !val;
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
      });
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList()),
        "homeChips": homeChips.map((c) => c.toJson()).toList(),
      });
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(List content,
      {bool isQuickPicks = false}) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e is AlbumContent) return e.toJson();
        if (e is SongContent) return e.toJson();
        if (e is ArtistShelf) return e.toJson();
        return (e as PlaylistContent).toJson();
      }).toList();
    }
  }

  void disposeContentScrollControllers() {
    for (final controller in _contentScrollControllers.values) {
      controller.dispose();
    }
    _contentScrollControllers.clear();
  }

  @override
  void onClose() {
    disposeContentScrollControllers();
    super.onClose();
  }
}
