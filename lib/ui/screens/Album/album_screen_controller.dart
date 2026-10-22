import 'dart:async';

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
import '../../theme/riff_tokens.dart';
import '../Library/library_controller.dart';
import 'more_by_artist.dart';
import '/ui/widgets/cover_hero.dart';
import 'package:harmonymusic/services/album_versions.dart';

///AlbumScreenController handles album screen
///
///Album title,image,songs
class AlbumScreenController extends PlaylistAlbumScreenControllerBase
    with AdditionalOpeartionMixin, GetSingleTickerProviderStateMixin {
  final album =
      Album(title: "", browseId: "", thumbnailUrl: "", artists: []).obs;

  /// The card cover flying in, if the page was opened from one
  /// ([CoverHero]); taken as the page opens.
  final Object? coverHeroTag = CoverHero.take();

  /// "More by …" under the album (Spotify, Apple Music): its first credited
  /// artist's other releases. Empty until they load, and offline.
  final moreByArtist = <Album>[].obs;
  String moreByArtistName = '';

  /// The album's other versions (a deluxe edition, a remaster), as its
  /// page lists them, and what the page calls them.
  final otherVersions = <Album>[].obs;
  String otherVersionsTitle = '';

  // Header fade-in, as the album's details arrive.
  late AnimationController _animationController;
  late CurvedAnimation _scaleAnimation;

  AnimationController get animationController => _animationController;
  Animation<double> get scaleAnimation => _scaleAnimation;

  @override
  void onInit() {
    super.onInit();
    _animationController = AnimationController(
      vsync: this,
      duration: RiffDurations.content,
    );

    _scaleAnimation = CurvedAnimation(
        parent: animationController, curve: RiffDurations.enterCurve);

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
        _takeOtherVersions(content);
      } else {
        // If the album is offline, fetch the songs from the local database
        // Album details are already fetched in _checkIfAddedToLibrary method
        final box = await Hive.openBox(albumId);
        songList.value = box.values
            .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
            .whereType<MediaItem>()
            .toList();
        // Saved: its page, for its other versions, when it can be reached.
        unawaited(_loadOtherVersions(albumId));
        // Shared box (Hive hands every caller the same instance): never close
        // it here, or the player and other screens using it fail mid-write.
      }
      checkDownloadStatus();
      unawaited(_loadMoreByArtist());
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
      // list shimmering forever. A saved album opened by its id has its
      // details by now too: its header shows (it never faded in before).
      if (!isClosed) {
        isContentFetched.value = true;
        if (album.value.browseId.isNotEmpty) animationController.forward();
      }
    }
  }

  void _takeOtherVersions(Map<String, dynamic> content) {
    final versions = content['otherVersions'];
    if (versions is! AlbumVersions) return;
    otherVersionsTitle = versions.title;
    otherVersions.value = versions.albums;
  }

  Future<void> _loadOtherVersions(String albumId) async {
    try {
      final content =
          await musicServices.getPlaylistOrAlbumSongs(albumId: albumId);
      if (!isClosed) _takeOtherVersions(content);
    } catch (e) {
      // Offline, or the page didn't load: no section.
      printERROR('Other versions: $e');
    }
  }

  /// More by the artist without the other versions shown above it.
  List<Album> get moreByArtistShown => [
        for (final a in moreByArtist)
          if (!otherVersions.any((v) => v.browseId == a.browseId)) a
      ];

  Future<void> _loadMoreByArtist() async {
    final artist = album.value.artists
        ?.firstWhereOrNull((a) => '${a['id'] ?? ''}'.isNotEmpty);
    if (artist == null) return;
    try {
      final page = await musicServices.getArtist('${artist['id']}');
      if (isClosed) return;
      moreByArtistName = '${artist['name'] ?? page['name'] ?? ''}';
      moreByArtist.value = moreByArtistAlbums(page, album.value.browseId,
          currentTitle: album.value.title);
    } catch (e) {
      // Offline, or the artist page didn't load: no section.
      printERROR('More by artist: $e');
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
    _scaleAnimation.dispose();
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
