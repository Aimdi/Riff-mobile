/// Spotify's offline mode, as YouTube Music and Apple Music behave too:
/// with no connection at all, with Offline mode turned on in Settings, or
/// on mobile data with Stream on Wi-Fi only (YouTube Music's Stream via
/// Wi-Fi only), songs that need one (YouTube songs neither downloaded nor
/// in the song cache) are passed over as play goes on, and their rows
/// dimmed, instead of each failing in turn until playback stops (or using
/// your data). Episodes, books and songs from your own servers go as
/// before.
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

  /// Whether the phone has a connection, and whether it costs data, as
  /// they change (Android): {online, metered}.
  static const channel = EventChannel('riff/network/online');

  /// AppPrefs: whether Offline mode is on.
  static const modeKey = 'offlineMode';

  /// Offline: no connection at all, as the phone says (false until it has,
  /// and off Android), or Offline mode on.
  static final offline = false.obs;

  /// Spotify's Offline mode, turned on in Settings: as with no connection,
  /// whatever the phone says, so songs not kept use no data.
  static final mode = false.obs;

  /// AppPrefs: whether songs stream on Wi-Fi only.
  static const wifiOnlyKey = 'streamOnWifiOnly';

  /// Stream on Wi-Fi only, turned on in Settings: on a connection that
  /// costs data it's as Offline mode, so only songs kept play there.
  static final wifiOnly = false.obs;

  /// No connection at all, as the phone says (Android): downloads wait
  /// for one (Downloader).
  static final noConnection = false.obs;

  /// The connection in use costs data (mobile data, a metered hotspot), as
  /// the phone says.
  static bool _metered = false;

  static bool get _wifiOnlyHolds => wifiOnly.value && _metered;

  static void _update() =>
      offline.value = noConnection.value || mode.value || _wifiOnlyHolds;

  static StreamSubscription<dynamic>? _watching;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Follows the connection from now on (once; Android only), Offline mode
  /// as it was left.
  static void watch() {
    mode.value = _prefs?.get(modeKey) == true;
    wifiOnly.value = _prefs?.get(wifiOnlyKey) == true;
    _update();
    if (_watching != null || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _watching = channel.receiveBroadcastStream().listen((event) {
      // {online, metered}; a bare online before Riff asked about data.
      noConnection.value = (event is Map ? event['online'] : event) == false;
      _metered = event is Map && event['metered'] == true;
      _update();
    }, onError: (_) {
      // Can't tell: online, on Wi-Fi, so nothing is passed over by mistake.
      noConnection.value = false;
      _metered = false;
      _update();
    });
  }

  /// Turns Offline mode on or off, kept across restarts.
  static Future<void> setMode(bool on) async {
    mode.value = on;
    _update();
    await _prefs?.put(modeKey, on);
  }

  /// Turns Stream on Wi-Fi only on or off, kept across restarts.
  static Future<void> setWifiOnly(bool on) async {
    wifiOnly.value = on;
    _update();
    await _prefs?.put(wifiOnlyKey, on);
  }

  /// Offline because Offline mode is on, or Stream on Wi-Fi only on mobile
  /// data, not for want of a connection.
  static bool get byChoice =>
      (mode.value || _wifiOnlyHolds) && !noConnection.value;

  /// What to say when a song that needs a connection doesn't play: there's
  /// none, Offline mode is on, or it's mobile data with Stream on Wi-Fi
  /// only (a translation key).
  static String get songMessageKey => noConnection.value
      ? 'offlineSongMsg'
      : mode.value
          ? 'offlineModeSongMsg'
          : _wifiOnlyHolds
              ? 'wifiOnlySongMsg'
              : 'offlineSongMsg';

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
    noConnection.value = false;
    _metered = false;
    mode.value = false;
    wifiOnly.value = false;
    offline.value = false;
  }
}
