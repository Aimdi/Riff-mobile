import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/playlist.dart';
import '../utils/helper.dart';
import '../utils/hive_boxes.dart';
import 'music_service.dart';
import 'utils.dart';
import 'yt_auth_service.dart';

/// Your YouTube Music playlists in Riff's Library, as Metrolist brings
/// them in: with your YouTube account connected, the playlists in your
/// YouTube Music library (yours and the ones you saved) are added to
/// Library › Playlists, those not there yet. They open as any YouTube
/// playlist saved in Riff does. Liked music comes in as your Favorites
/// (YtLikeSync) and Episodes for later isn't music, so neither comes.
class YtPlaylistsImport {
  YtPlaylistsImport._();

  static const libraryBox = 'LibraryPlaylists';

  /// Liked music and Episodes for later.
  static const _notPlaylists = {'LM', 'SE'};

  /// Whether the playlists are coming in now.
  static final importing = false.obs;

  /// Your YouTube Music library's playlists; tests replace it.
  @visibleForTesting
  static Future<List<Playlist>> Function() fetch =
      () => Get.find<MusicServices>().getLibraryPlaylists();

  /// Whether a YouTube account is connected; tests replace it.
  @visibleForTesting
  static bool Function() connected = () => YtAuthService.isConnected;

  /// Adds the playlists of your YouTube Music library that Library ›
  /// Playlists doesn't have yet (under either form of their id, VL… or
  /// not). How many came; null when they couldn't be read (or already
  /// coming).
  static Future<int?> importPlaylists() async {
    if (!connected() || importing.value) return null;
    importing.value = true;
    try {
      final playlists = await fetch();
      final box = await HiveBoxes.open(libraryBox);
      bool saved(String id) => box.containsKey(id) || box.containsKey('VL$id');
      final fresh = <String, dynamic>{
        for (final playlist in playlists)
          if (validatePlaylistId(playlist.playlistId) case final id
              when id.isNotEmpty && !_notPlaylists.contains(id) && !saved(id))
            playlist.playlistId: playlist.toJson(),
      };
      if (fresh.isNotEmpty) await box.putAll(fresh);
      return fresh.length;
    } catch (e) {
      printERROR('YouTube Music playlists not read: $e');
      return null;
    } finally {
      importing.value = false;
    }
  }
}
