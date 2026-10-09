import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../widgets/add_to_playlist.dart';
import '/ui/widgets/sort_widget.dart';
import '../../../models/artist.dart';
import '../../../models/thumbnail.dart';
import '../../../utils/helper.dart';
import '../Library/library_controller.dart';
import '/services/discovery/discovery_service.dart';
import '/services/music_service.dart';

class ArtistScreenController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final isArtistContentFetced = false.obs;

  /// The artist could not be loaded (offline, or not an artist channel).
  final artistLoadFailed = false.obs;
  String _artistId = '';
  final navigationRailCurrentIndex = 0.obs;
  final musicServices = Get.find<MusicServices>();
  final railItems = <String>[].obs;
  final artistData = <String, dynamic>{}.obs;
  final sepataredContent = <String, dynamic>{}.obs;
  final isSeparatedArtistContentFetced = false.obs;
  final isAddedToLibrary = false.obs;
  final songScrollController = ScrollController();
  final videoScrollController = ScrollController();
  final albumScrollController = ScrollController();
  final singlesScrollController = ScrollController();
  SortWidgetController? sortWidgetController;
  final additionalOperationMode = OperationMode.none.obs;
  bool continuationInProgress = false;
  late Artist artist_;
  Map<String, List> tempListContainer = {};
  TabController? tabController;
  bool isTabTransitionReversed = false;

  @override
  void onInit() {
    final args = Get.arguments;
    _init(args[0], args[1]);
    if (GetPlatform.isDesktop) {
      tabController = TabController(vsync: this, length: 5);
      tabController?.animation?.addListener(() {
        int indexChange = tabController!.offset.round();
        int index = tabController!.index + indexChange;

        if (index != navigationRailCurrentIndex.value) {
          onDestinationSelected(index);
          navigationRailCurrentIndex.value = index;
        }
      });
    }
    super.onInit();
  }

  _init(bool isIdOnly, dynamic artist) {
    if (!isIdOnly) artist_ = artist as Artist;
    _fetchArtistContent(isIdOnly ? artist as String : artist.browseId);
    _checkIfAddedToLibrary(isIdOnly ? artist as String : artist.browseId);
  }

  Future<void> _checkIfAddedToLibrary(String id) async {
    final box = await Hive.openBox("LibraryArtists");
    isAddedToLibrary.value = box.containsKey(id);
    // Not closed: the Library tab and other artist pages share this box, and
    // closing it under them throws "Box has already been closed".
  }

  /// Tries the artist again after [artistLoadFailed].
  void retryArtistContent() => _fetchArtistContent(_artistId);

  Future<void> _fetchArtistContent(String id) async {
    _artistId = id;
    artistLoadFailed.value = false;
    try {
      artistData.value = await musicServices.getArtist(id);
    } catch (e) {
      // Offline, or a channel link that isn't an artist (no header).
      printERROR('Artist $id failed to load: $e');
      artistLoadFailed.value = true;
      return;
    }
    artistData["Singles"] = artistData["Singles & EPs"];
    artistData["Songs"] = artistData["Top songs"];
    isArtistContentFetced.value = true;
    //inspect(artistData.value);
    final data = artistData;
    artist_ = Artist(
        browseId: id,
        name: data['name'],
        thumbnailUrl: Thumbnail.bestUrl(data['thumbnails'], target: 'high'),
        subscribers: "${data['subscribers']} subscribers",
        radioId: data["radioId"]);
  }

  Future<bool> addNremoveFromLibrary({bool add = true}) async {
    try {
      final box = await Hive.openBox("LibraryArtists");
      add
          ? box.put(artist_.browseId, artist_.toJson())
          : box.delete(artist_.browseId);
      isAddedToLibrary.value = add;
      // Discovery: LibraryArtists acts as follow for Release Radar.
      if (Get.isRegistered<DiscoveryService>()) {
        final disc = Get.find<DiscoveryService>();
        if (add) {
          await disc.repo.followArtist(artist_.browseId,
              name: artist_.name, thumbnailUrl: artist_.thumbnailUrl);
        } else {
          await disc.repo.unfollowArtist(artist_.browseId);
        }
        await disc.onFollow(artist_.name, follow: add);
      }
      //Update frontend
      Get.find<LibraryArtistsController>().refreshLib();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// List loads in flight, by tab: opening a tab again while it is still
  /// loading waits for that request instead of sending a second one (and
  /// stacking a second load-more listener).
  final Map<String, Future<void>> _tabLoads = {};

  Future<void> onDestinationSelected(int val) async {
    isTabTransitionReversed = val > navigationRailCurrentIndex.value;
    navigationRailCurrentIndex.value = val;
    final tabName = ["About", "Songs", "Videos", "Albums", "Singles"][val];

    //cancel additional operations in case of tab change
    if (sortWidgetController != null) {
      sortWidgetController?.setActiveMode(OperationMode.none);
      cancelAdditionalOperation();
    }

    //skip for about page
    if (val == 0) return;
    if (sepataredContent.containsKey(tabName)) {
      // Already loaded: another tab's load still running must not keep
      // this list behind the shimmer.
      isSeparatedArtistContentFetced.value = true;
      return;
    }
    if (artistData[tabName] == null) {
      isSeparatedArtistContentFetced.value = true;
      return;
    }
    isSeparatedArtistContentFetced.value = false;
    await (_tabLoads[tabName] ??= _loadTab(val, tabName).whenComplete(() {
      _tabLoads.remove(tabName);
    }));
    // A slower load for a tab the user has left doesn't mark the tab now
    // on screen as loaded.
    if (!isClosed && navigationRailCurrentIndex.value == val) {
      isSeparatedArtistContentFetced.value = true;
    }
  }

  Future<void> _loadTab(int val, String tabName) async {
    //check if params available for continuation
    //tab browse endpoint & top result stored in [artistData], tabContent & addtionalParams for continuation stored in Separated Content
    if ((artistData[tabName]).containsKey("params")) {
      try {
        final content = await musicServices.getArtistRealtedContent(
            artistData[tabName], tabName);
        // Closed meanwhile: its scroll controllers are disposed.
        if (isClosed) return;
        sepataredContent[tabName] = content;
      } catch (e) {
        // Fall back to the overview shelf instead of loading forever.
        printERROR('Artist "$tabName" list failed: $e');
        sepataredContent[tabName] = {
          "results": List.from(artistData[tabName]['content'] ?? const []),
          "additionalParams": '&ctoken=null&continuation=null',
        };
        return;
      }
    } else {
      sepataredContent[tabName] = {"results": artistData[tabName]['content']};
      return;
    }

    // Loads the next page once the list is scrolled halfway. A loaded tab
    // is never fetched again, so this runs once per tab.
    final scrollController = val == 1
        ? songScrollController
        : val == 2
            ? videoScrollController
            : val == 3
                ? albumScrollController
                : singlesScrollController;

    scrollController.addListener(() {
      double maxScroll = scrollController.position.maxScrollExtent;
      double currentScroll = scrollController.position.pixels;
      if (currentScroll >= maxScroll / 2 &&
          sepataredContent[tabName]['additionalParams'] !=
              '&ctoken=null&continuation=null') {
        if (!continuationInProgress) {
          continuationInProgress = true;
          getContinuationContents(artistData[tabName], tabName);
        }
      }
    });
  }

  Future<void> getContinuationContents(browseEndpoint, tabName) async {
    try {
      final x = await musicServices.getArtistRealtedContent(
          browseEndpoint, tabName,
          additionalParams: sepataredContent[tabName]['additionalParams']);
      (sepataredContent[tabName]['results']).addAll(x['results']);
      sepataredContent[tabName]['additionalParams'] = x['additionalParams'];
      sepataredContent.refresh();
    } catch (e) {
      printERROR('Artist "$tabName" continuation failed: $e');
    } finally {
      // Without this a single failure blocks all further paging.
      continuationInProgress = false;
    }
  }

  void onSort(SortType sortType, bool isAscending, String title) {
    if (sepataredContent[title] == null) {
      return;
    }
    if (title == "Songs" || title == "Videos") {
      final songlist = sepataredContent[title]['results'].toList();
      sortSongsNVideos(songlist, sortType, isAscending);
      sepataredContent[title]['results'] = songlist;
    } else if (title == "Albums" || title == "Singles") {
      final albumList = sepataredContent[title]['results'].toList();
      sortAlbumNSingles(albumList, sortType, isAscending);
      sepataredContent[title]['results'] = albumList;
    }
    sepataredContent.refresh();
  }

  void onSearchStart(String? tag) {
    final title = tag?.split("_")[0];
    tempListContainer[title!] = sepataredContent[title]['results'].toList();
  }

  void onSearch(String value, String? tag) {
    final title = tag?.split("_")[0];
    final list = tempListContainer[title]!
        .where((element) =>
            element.title.toLowerCase().contains(value.toLowerCase()))
        .toList();
    sepataredContent[title]['results'] = list;
    sepataredContent.refresh();
  }

  void onSearchClose(String? tag) {
    final title = tag?.split("_")[0];
    sepataredContent[title]['results'] = (tempListContainer[title]!).toList();
    sepataredContent.refresh();
    (tempListContainer[title]!).clear();
  }

  //Additional operations
  final additionalOperationTempList = <MediaItem>[].obs;
  final additionalOperationTempMap = <int, bool>{}.obs;

  void startAdditionalOperation(
      SortWidgetController sortWidgetController_, OperationMode mode) {
    sortWidgetController = sortWidgetController_;
    final tabName = [
      "About",
      "Songs",
      "Videos",
      "Albums",
      "Singles"
    ][navigationRailCurrentIndex.value];
    additionalOperationTempList.value =
        sepataredContent[tabName]['results'].toList();
    if (mode == OperationMode.addToPlaylist || mode == OperationMode.delete) {
      for (int i = 0; i < additionalOperationTempList.length; i++) {
        additionalOperationTempMap[i] = false;
      }
    }
    additionalOperationMode.value = mode;
  }

  void checkIfAllSelected() {
    sortWidgetController!.isAllSelected.value =
        !additionalOperationTempMap.containsValue(false);
  }

  void selectAll(bool selected) {
    for (int i = 0; i < additionalOperationTempList.length; i++) {
      additionalOperationTempMap[i] = selected;
    }
  }

  void performAdditionalOperation() {
    final currMode = additionalOperationMode.value;
    if (currMode == OperationMode.addToPlaylist) {
      final ctx = Get.context;
      if (ctx == null) return;
      showAddToPlaylistSheet(ctx, selectedSongs()).whenComplete(() {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    }
  }

  List<MediaItem> selectedSongs() {
    return additionalOperationTempMap.entries
        .map((item) {
          if (item.value) {
            return additionalOperationTempList[item.key];
          }
        })
        .whereType<MediaItem>()
        .toList();
  }

  void cancelAdditionalOperation() {
    sortWidgetController!.isAllSelected.value = false;
    sortWidgetController = null;
    additionalOperationMode.value = OperationMode.none;
    additionalOperationTempList.clear();
    additionalOperationTempMap.clear();
  }

  @override
  void onClose() {
    tempListContainer.clear();
    songScrollController.dispose();
    videoScrollController.dispose();
    albumScrollController.dispose();
    singlesScrollController.dispose();
    tabController?.dispose();
    super.onClose();
  }
}
