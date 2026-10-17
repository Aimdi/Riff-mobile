/// Autoplay (Spotify's, YouTube Music's, Apple Music's ∞): when the songs
/// you picked run out, songs like the last of them play on, as radio from
/// it. Off by default; music only.
library;

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_item_extras.dart';

class MusicAutoplay {
  MusicAutoplay._();

  /// AppPrefs key.
  static const key = 'musicAutoplay';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// For the Settings switch and the queue's ∞ button.
  static final enabled = RxBool(_prefs?.get(key) == true);

  static Future<void> set(bool on) async {
    enabled.value = on;
    await _prefs?.put(key, on);
  }

  /// Whether Autoplay plays on after [song] ends the queue: when it's on,
  /// and [song] is a song (nothing is "like" a podcast episode or a book's
  /// chapter to YouTube Music; those queues end as they did).
  static bool after(MediaItem? song) =>
      enabled.value &&
      song != null &&
      song.id.isNotEmpty &&
      !song.isPodcastEpisode &&
      !song.isAudiobook;
}
