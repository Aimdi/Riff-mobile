/// Spotify's offline mode, as YouTube Music and Apple Music behave too:
/// with no connection at all, songs that need one (YouTube songs neither
/// downloaded nor in the song cache) are passed over as play goes on, and
/// their rows dimmed, instead of each failing in turn until playback
/// stops. Episodes, books and songs from your own servers go as before.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_item_extras.dart';

class OfflinePlayback {
  OfflinePlayback._();

  /// Whether the phone has a connection, as it comes and goes (Android).
  static const channel = EventChannel('riff/network/online');

  /// No connection at all, as the phone says; false until it has, and off
  /// Android.
  static final offline = false.obs;

  static StreamSubscription<dynamic>? _watching;

  /// Follows the connection from now on (once; Android only).
  static void watch() {
    if (_watching != null || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _watching = channel
        .receiveBroadcastStream()
        .listen((online) => offline.value = online == false,
            // Can't tell: online, so nothing is passed over by mistake.
            onError: (_) => offline.value = false);
  }

  /// Ids of what plays from elsewhere than YouTube: episodes, Audiobookshelf
  /// and LibriVox books, your music server, Soulseek.
  static const _otherSources = ['podcast_', 'abs_', 'lv_', 'cloud_', 'slsk_'];

  /// Whether [song] needs a connection to play: a YouTube song that's
  /// neither downloaded nor in the song cache.
  static bool needsConnection(MediaItem song) {
    if (song.isPodcastEpisode ||
        song.streamSource != null ||
        _otherSources.any(song.id.startsWith)) {
      return false;
    }
    return !_kept('SongDownloads', song.id) && !_kept('SongsCache', song.id);
  }

  /// In [box]; when it isn't open (so can't tell), as if it were.
  static bool _kept(String box, String id) =>
      !Hive.isBoxOpen(box) || Hive.box(box).containsKey(id);

  /// Whether [song] can't play now: offline, and it needs a connection.
  static bool blocks(MediaItem? song) =>
      offline.value && song != null && needsConnection(song);

  @visibleForTesting
  static Future<void> resetForTest() async {
    await _watching?.cancel();
    _watching = null;
    offline.value = false;
  }
}
