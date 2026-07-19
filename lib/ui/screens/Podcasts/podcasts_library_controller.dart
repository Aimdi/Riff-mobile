import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/playlist.dart';
import '/services/music_service.dart';
import '/ui/widgets/sort_widget.dart';

class LibraryPodcastsController extends GetxController {
  final libraryPodcasts = <Playlist>[].obs;
  final topEpisodes = <MediaItem>[].obs;
  final featuredPodcasts = <Playlist>[].obs;

  final isDiscoveryLoading = false.obs;
  final discoveryError = false.obs;
  final isContentFetched = false.obs;

  List<Playlist> tempListContainer = [];

  @override
  void onInit() {
    super.onInit();
    refreshLib();
    loadDiscovery();
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
    if (!force &&
        (topEpisodes.isNotEmpty || featuredPodcasts.isNotEmpty)) {
      return;
    }
    isDiscoveryLoading.value = true;
    discoveryError.value = false;
    try {
      final data = await Get.find<MusicServices>().getPodcastDiscovery();
      topEpisodes.assignAll(
          List<MediaItem>.from(data['topEpisodes'] ?? const []));
      featuredPodcasts.assignAll(
          List<Playlist>.from(data['featuredPodcasts'] ?? const []));
    } catch (_) {
      discoveryError.value = true;
    } finally {
      isDiscoveryLoading.value = false;
    }
  }

  Future<void> addToLibrary(Playlist podcast) async {
    final box = await Hive.openBox('LibraryPodcasts');
    final id = podcast.playlistId;
    final toStore = podcast.copyWith(kind: 'podcast');
    await box.put(id, {
      ...toStore.toJson(),
      'kind': 'podcast',
      'description': podcast.description ?? 'Podcast',
    });
    await refreshLib();
  }

  Future<void> removeFromLibrary(String playlistId) async {
    final box = await Hive.openBox('LibraryPodcasts');
    await box.delete(playlistId);
    await refreshLib();
  }

  bool isInLibrary(String playlistId) {
    return libraryPodcasts.any((p) => p.playlistId == playlistId);
  }

  void onSort(SortType sortType, bool isAscending) {
    final list = libraryPodcasts.toList();
    switch (sortType) {
      case SortType.Name:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      default:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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
