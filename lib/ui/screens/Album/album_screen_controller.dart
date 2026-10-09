import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/base_class/playlist_album_screen_con_base.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';

import '../../../mixins/additional_opeartion_mixin.dart';
import '../../../models/media_Item_builder.dart';
import '../Library/library_controller.dart';

///AlbumScreenController handles album screen
///
///Album title,image,songs
class AlbumScreenController extends PlaylistAlbumScreenControllerBase
    with AdditionalOpeartionMixin, GetSingleTickerProviderStateMixin {
  final album =
      Album(title: "", browseId: "", thumbnailUrl: "", artists: []).obs;

  // Title animation
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  AnimationController get animationController => _animationController;
  Animation<double> get scaleAnimation => _scaleAnimation;


  @override
  void onInit() {
    super.onInit();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(begin: 0, end: 1.0).animate(animationController);

    final args = Get.arguments as (Album?, String);
    fetchAlbumDetails(args.$1, args.$2);
  }

  @override
  void fetchAlbumDetails(Album? album_, String albumId) async {
    try {
      if (album_ != null) {
        album.value = album_;
        animationController.forward();
      }
      // Check if the album is offline
      if (!await checkIfAddedToLibrary(albumId)) {
        // Fetch album details online
        final content =
            await musicServices.getPlaylistOrAlbumSongs(albumId: albumId);
        content['browseId'] = albumId;
        album.value = Album.fromJson(content);
        animationController.forward();
        songList.value = List<MediaItem>.from(content['tracks']);
      } else {
        // If the album is offline, fetch the songs from the local database
        // Album details are already fetched in _checkIfAddedToLibrary method
        final box = await Hive.openBox(albumId);
        songList.value = box.values
            .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
            .whereType<MediaItem>()
            .toList();
        // Shared box (Hive hands every caller the same instance): never close
        // it here, or the player and other screens using it fail mid-write.
      }
      checkDownloadStatus();
    } catch (e) {
      // Handle any errors that occur during the fetch
      printERROR("Error fetching album details: $e");
      final ctx = Get.context;
      if (!isClosed && ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
            snackbar(ctx, "networkError".tr, size: SanckBarSize.MEDIUM));
      }
    } finally {
      // As on the playlist page: a failed load must not leave the track
      // list shimmering forever.
      if (!isClosed) isContentFetched.value = true;
    }
  }

  @override
  Future<bool> checkIfAddedToLibrary(String id) async {
    final box = await Hive.openBox("LibraryAlbums");
    isAddedToLibrary.value = box.containsKey(id);
    if (isAddedToLibrary.value) album.value = Album.fromJson(box.get(id));
    // Not closed: shared with the Library tab (see ArtistScreenController).
    return isAddedToLibrary.value;
  }

  @override
  Future<bool> addNremoveFromLibrary(content, {bool add = true}) async {
    try {
      final box = await Hive.openBox("LibraryAlbums");
      final id = content.browseId;
      if (add) {
        box.put(id, content.toJson());
        updateSongsIntoDb();
      } else {
        box.delete(id);
        final songsBox = await Hive.openBox(id);
        songsBox.deleteFromDisk();
      }
      isAddedToLibrary.value = add;

      //Update frontend
      Get.find<LibraryAlbumsController>().refreshLib();

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateSongsIntoDb() async {
    final songsBox = await Hive.openBox(album.value.browseId);
    await songsBox.clear();
    final songListCopy = songList.toList();
    for (int i = 0; i < songListCopy.length; i++) {
      await songsBox.put(i, MediaItemBuilder.toJson(songListCopy[i]));
    }
    // Shared box (Hive hands every caller the same instance): never close
    // it here, or the player and other screens using it fail mid-write.
  }

  @override
  void onClose() {
    tempListContainer.clear();
    _animationController.dispose();
    super.onClose();
  }

  @override
  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {}

  @override
  void fetchPlaylistDetails(Playlist? playlist_, String playlistId) {}

  @override
  Future<bool> syncPlaylistSongs() async => false;
}
