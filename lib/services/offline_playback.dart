/// Spotify's offline mode, as YouTube Music and Apple Music behave too:
/// with no connection at all, or with Offline mode turned on in Settings,
/// songs that need one (YouTube songs neither downloaded nor in the song
/// cache) are passed over as play goes on, and their rows dimmed, instead
/// of each failing in turn until playback stops (or using your data).
/// Episodes, books and songs from your own servers go as before.
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

  /// AppPrefs: whether Offline mode is on.
  static const modeKey = 'offlineMode';

  /// Offline: no connection at all, as the phone says (false until it has,
  /// and off Android), or Offline mode on.
  static final offline = false.obs;

  /// Spotify's Offline mode, turned on in Settings: as with no connection,
  /// whatever the phone says, so songs not kept use no data.
  static final mode = false.obs;

  /// No connection at all, as the phone says.
  static bool _noConnection = false;

  static void _update() => offline.value = _noConnection || mode.value;

  static StreamSubscription<dynamic>? _watching;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Follows the connection from now on (once; Android only), Offline mode
  /// as it was left.
  static void watch() {
    mode.value = _prefs?.get(modeKey) == true;
    _update();
    if (_watching != null || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _watching = channel.receiveBroadcastStream().listen((online) {
      _noConnection = online == false;
      _update();
    }, onError: (_) {
      // Can't tell: online, so nothing is passed over by mistake.
      _noConnection = false;
      _update();
    });
  }

  /// Turns Offline mode on or off, kept across restarts.
  static Future<void> setMode(bool on) async {
    mode.value = on;
    _update();
    await _prefs?.put(modeKey, on);
  }

  /// Offline because Offline mode is on, not for want of a connection.
  static bool get byChoice => mode.value && !_noConnection;

  /// Ids of what plays from elsewhere than YouTube: episodes, Audiobookshelf
  /// and LibriVox books, your music server, Soulseek, the phone's own music
  /// files.
  static const _otherSources = [
    'podcast_',
    'abs_',
    'lv_',
    'cloud_',
    'slsk_',
    'device_',
  ];

  /// Whether the song with this id plays from YouTube (by its id alone).
  static bool playsFromYouTube(String id) => !_otherSources.any(id.startsWith);

  /// Whether [song] needs a connection to play: a YouTube song that's
  /// neither downloaded nor in the song cache.
  static bool needsConnection(MediaItem song) {
    if (song.isPodcastEpisode ||
        song.streamSource != null ||
        !playsFromYouTube(song.id)) {
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
    _noConnection = false;
    mode.value = false;
    offline.value = false;
  }
}
