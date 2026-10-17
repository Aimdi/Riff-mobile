import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'music_service.dart';
import 'private_session.dart';
import 'yt_auth_service.dart';

/// What you play in Riff counted in your YouTube Music history once your
/// YouTube account is connected, as YouTube Music's own app counts it
/// (and Metrolist, InnerTune): a song or video that starts playing (a
/// YouTube podcast episode too) goes into the account's History, which its
/// Listen again, mixes and recommendations learn from, so the feed Riff
/// shows you does too. On unless switched off. What a private session
/// plays, or a playlist left out of your taste profile, isn't counted, as
/// Riff keeps it out of its own history and taste.
class YtHistorySync {
  YtHistorySync._();

  /// AppPrefs: whether plays are counted (on unless switched off).
  static const enabledKey = 'ytHistorySync';

  /// Bumps when the switch changes.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static bool get enabled => _prefs?.get(enabledKey) != false;

  static Future<void> setEnabled(bool on) async {
    await _prefs?.put(enabledKey, on);
    rev.value++;
  }

  /// Whether a YouTube account is connected; tests replace it.
  @visibleForTesting
  static bool Function() connected = () => YtAuthService.isConnected;

  /// Counts a play of [videoId] in the connected account's history;
  /// whether YouTube took it. Tests replace it.
  @visibleForTesting
  static Future<bool> Function(String videoId) send =
      (videoId) => Get.find<MusicServices>().registerPlayback(videoId);

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Riff's own ids (a phone song, a music server's, a feed's episode, a
  /// book, a Soulseek file), which can look like a video's.
  static const _notYouTube = [
    'device_',
    'cloud_',
    'podcast_',
    'abs_',
    'lv_',
    'slsk_',
  ];

  /// Whether [song] is one YouTube's history can have: a YouTube song or
  /// video, not a phone song, a music server's, a feed's episode or a book.
  static bool counts(MediaItem song) =>
      _videoId.hasMatch(song.id) && !_notYouTube.any(song.id.startsWith);

  /// [song] started playing (a new play, neither private nor left out of
  /// your taste): counted in the connected account's history while it's
  /// on. Whether YouTube took it.
  static Future<bool> notePlay(MediaItem song) async {
    if (!enabled || !connected() || !counts(song)) return false;
    if (PrivateSession.isActive) return false;
    try {
      return await send(song.id);
    } catch (e) {
      printERROR('YouTube Music history (${song.id}): $e');
      return false;
    }
  }
}
