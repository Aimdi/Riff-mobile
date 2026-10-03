import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// How much the podcast voice boost lifts quiet speech, as a gain on the
/// native loudness enhancer that already sits on the player's session.
enum PodcastVoiceBoost {
  off(0),
  low(500),
  high(1000);

  const PodcastVoiceBoost(this.loudnessMb);

  /// Target gain in millibels (100 mB = 1 dB).
  final int loudnessMb;

  static PodcastVoiceBoost fromName(Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return PodcastVoiceBoost.off;
  }
}

/// Playback settings for podcast episodes: the global defaults, or one
/// show's overrides. Never applied to music.
class PodcastPlaybackProfile {
  const PodcastPlaybackProfile({
    this.speed = 1.0,
    this.skipBackSec = 10,
    this.skipForwardSec = 30,
    this.trimSilence = false,
    this.voiceBoost = PodcastVoiceBoost.off,
    this.segmentSkip = true,
  });

  final double speed;
  final int skipBackSec;
  final int skipForwardSec;
  final bool trimSilence;
  final PodcastVoiceBoost voiceBoost;

  /// Skip ad / sponsor segments (chapter ads, SponsorBlock) for this show.
  final bool segmentSkip;

  static const minSpeed = 0.5;
  static const maxSpeed = 3.0;
  static const speedChips = [1.0, 1.1, 1.25, 1.5, 2.0];
  static const skipChoices = [5, 10, 15, 30, 45, 60];

  /// Clamps to 0.5–3.0 and rounds to two decimals so 1.25 survives while
  /// slider noise like 1.2000000001 does not.
  static double snapSpeed(num? value) {
    final v = (value ?? 1.0).toDouble();
    if (v.isNaN) return 1.0;
    final clamped = v.clamp(minSpeed, maxSpeed).toDouble();
    return (clamped * 100).round() / 100;
  }

  /// The allowed skip length closest to [value].
  static int snapSkip(num? value, {required int fallback}) {
    if (value == null) return fallback;
    final v = value.toDouble();
    if (v.isNaN) return fallback;
    var best = skipChoices.first;
    for (final c in skipChoices) {
      if ((c - v).abs() < (best - v).abs()) best = c;
    }
    return best;
  }

  /// Reads a stored map, tolerating missing keys, wrong types and values
  /// out of range (old or hand-edited data must never crash playback).
  factory PodcastPlaybackProfile.fromMap(Object? raw,
      {PodcastPlaybackProfile fallback = const PodcastPlaybackProfile()}) {
    if (raw is! Map) return fallback;
    bool boolOr(Object? v, bool d) => v is bool ? v : d;
    final speed = raw['speed'];
    return PodcastPlaybackProfile(
      speed: speed is num ? snapSpeed(speed) : fallback.speed,
      skipBackSec: snapSkip(raw['skipBack'] is num ? raw['skipBack'] : null,
          fallback: fallback.skipBackSec),
      skipForwardSec: snapSkip(
          raw['skipForward'] is num ? raw['skipForward'] : null,
          fallback: fallback.skipForwardSec),
      trimSilence: boolOr(raw['trimSilence'], fallback.trimSilence),
      voiceBoost: raw.containsKey('voiceBoost')
          ? PodcastVoiceBoost.fromName(raw['voiceBoost'])
          : fallback.voiceBoost,
      segmentSkip: boolOr(raw['segmentSkip'], fallback.segmentSkip),
    );
  }

  Map<String, Object> toMap() => {
        'speed': speed,
        'skipBack': skipBackSec,
        'skipForward': skipForwardSec,
        'trimSilence': trimSilence,
        'voiceBoost': voiceBoost.name,
        'segmentSkip': segmentSkip,
      };

  PodcastPlaybackProfile copyWith({
    double? speed,
    int? skipBackSec,
    int? skipForwardSec,
    bool? trimSilence,
    PodcastVoiceBoost? voiceBoost,
    bool? segmentSkip,
  }) =>
      PodcastPlaybackProfile(
        speed: speed == null ? this.speed : snapSpeed(speed),
        skipBackSec: skipBackSec ?? this.skipBackSec,
        skipForwardSec: skipForwardSec ?? this.skipForwardSec,
        trimSilence: trimSilence ?? this.trimSilence,
        voiceBoost: voiceBoost ?? this.voiceBoost,
        segmentSkip: segmentSkip ?? this.segmentSkip,
      );

  @override
  bool operator ==(Object other) =>
      other is PodcastPlaybackProfile &&
      other.speed == speed &&
      other.skipBackSec == skipBackSec &&
      other.skipForwardSec == skipForwardSec &&
      other.trimSilence == trimSilence &&
      other.voiceBoost == voiceBoost &&
      other.segmentSkip == segmentSkip;

  @override
  int get hashCode => Object.hash(
      speed, skipBackSec, skipForwardSec, trimSilence, voiceBoost, segmentSkip);

  @override
  String toString() => 'PodcastPlaybackProfile(${toMap()})';
}

/// Global podcast defaults before the user ever opened Podcast settings:
/// carried over from what podcasts played with until now (the app-wide
/// speed and trim-silence settings, -10 s / +30 s, the ad-skip toggle), so
/// updating changes nothing until the user does.
PodcastPlaybackProfile seedPodcastDefaults({
  Object? stored,
  Object? appSpeed,
  Object? appSkipSilence,
  Object? autoSkipAds,
}) {
  final legacy = PodcastPlaybackProfile(
    speed: appSpeed is num ? PodcastPlaybackProfile.snapSpeed(appSpeed) : 1.0,
    trimSilence: appSkipSilence is bool ? appSkipSilence : false,
    segmentSkip: autoSkipAds is bool ? autoSkipAds : true,
  );
  final base = PodcastPlaybackProfile.fromMap(stored, fallback: legacy);
  // The ad-skip toggle stays the one source of truth for the global
  // segment-skip default (it is read by the player directly).
  return autoSkipAds is bool ? base.copyWith(segmentSkip: autoSkipAds) : base;
}

/// The key a show's overrides are stored under: the feed URL for RSS
/// shows, `yt:<playlist id>` for YouTube shows (VL / MPSP prefixes are
/// dropped so YouTube Music and YouTube agree). Null when unknown.
String? podcastShowKeyForFeed(String? feedUrl) {
  final f = feedUrl?.trim() ?? '';
  return f.isEmpty ? null : f;
}

String? podcastShowKeyForYoutube(String? playlistId) {
  var id = playlistId?.trim() ?? '';
  if (id.startsWith('VL')) id = id.substring(2);
  if (id.startsWith('MPSP')) id = id.substring(4);
  return id.isEmpty ? null : 'yt:$id';
}

String? podcastShowKey(MediaItem item) {
  final extras = item.extras ?? const {};
  return podcastShowKeyForFeed(extras['feedUrl'] as String?) ??
      podcastShowKeyForYoutube(extras['podcastPlaylistId'] as String?);
}

/// Smart resume: how far to rewind when playback resumes after a pause of
/// [paused], so the listener catches the thread again.
Duration smartResumeRewind(Duration paused) {
  if (paused < const Duration(seconds: 5)) return Duration.zero;
  if (paused <= const Duration(minutes: 1)) return const Duration(seconds: 3);
  if (paused <= const Duration(minutes: 10)) return const Duration(seconds: 5);
  return const Duration(seconds: 10);
}

/// Where playback resumes after [rewind] from [position], never before 0.
Duration smartResumeTarget(Duration position, Duration rewind) {
  final t = position - rewind;
  return t.isNegative ? Duration.zero : t;
}

/// Sleep-timer fade: the volume factor (1 → 0) [elapsed] into a fade of
/// [length]. Linear, clamped.
double sleepFadeFactor(Duration elapsed, Duration length) {
  if (length <= Duration.zero) return 0;
  final t = elapsed.inMilliseconds / length.inMilliseconds;
  return (1 - t).clamp(0.0, 1.0);
}

/// Wall-clock time left until [remainingContent] has played at [speed].
Duration wallClockRemaining(Duration remainingContent, double speed) {
  final s = speed <= 0 ? 1.0 : speed;
  return Duration(milliseconds: (remainingContent.inMilliseconds / s).round());
}

/// Persisted podcast playback settings: global defaults in AppPrefs, one
/// map per show in the `PodcastShowPrefs` box. Every read tolerates a box
/// that isn't open yet (tests, first frames) by falling back.
class PodcastPlaybackPrefs {
  PodcastPlaybackPrefs._();

  static const showBox = 'PodcastShowPrefs';
  static const defaultsKey = 'podcastPlaybackDefaults';
  static const smartResumeKey = 'podcastSmartResume';
  static const autoSkipAdsKey = 'podcastAutoSkipAds';

  /// Bumped on every change so Obx widgets showing a profile rebuild.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;
  static Box? get _shows => Hive.isBoxOpen(showBox) ? Hive.box(showBox) : null;

  static PodcastPlaybackProfile get globalDefaults {
    final p = _prefs;
    if (p == null) return const PodcastPlaybackProfile();
    return seedPodcastDefaults(
      stored: p.get(defaultsKey),
      appSpeed: p.get('playbackSpeed'),
      appSkipSilence: p.get('skipSilenceEnabled'),
      autoSkipAds: p.get(autoSkipAdsKey),
    );
  }

  static Future<void> setGlobalDefaults(PodcastPlaybackProfile profile) async {
    final p = _prefs;
    if (p == null) return;
    await p.put(defaultsKey, profile.toMap());
    await p.put(autoSkipAdsKey, profile.segmentSkip);
    rev.value++;
  }

  static bool get smartResume {
    final v = _prefs?.get(smartResumeKey);
    return v is bool ? v : true;
  }

  static Future<void> setSmartResume(bool on) async {
    await _prefs?.put(smartResumeKey, on);
    rev.value++;
  }

  static PodcastPlaybackProfile? showOverride(String? key) {
    if (key == null) return null;
    final raw = _shows?.get(key);
    if (raw is! Map) return null;
    return PodcastPlaybackProfile.fromMap(raw, fallback: globalDefaults);
  }

  static bool hasShowOverride(String? key) =>
      key != null && _shows?.get(key) is Map;

  static Future<void> setShowOverride(
      String key, PodcastPlaybackProfile profile) async {
    final box = _shows ?? await Hive.openBox(showBox);
    await box.put(key, profile.toMap());
    rev.value++;
  }

  static Future<void> clearShowOverride(String key) async {
    await _shows?.delete(key);
    rev.value++;
  }

  /// The profile a show plays with: its overrides, else the defaults.
  static PodcastPlaybackProfile forShow(String? key) =>
      showOverride(key) ?? globalDefaults;

  static PodcastPlaybackProfile forItem(MediaItem item) =>
      forShow(podcastShowKey(item));

  /// Saves [profile] where [key]'s settings currently live: the show's
  /// overrides when it has them, else the global defaults.
  static Future<void> saveForShow(
      String? key, PodcastPlaybackProfile profile) async {
    if (hasShowOverride(key)) {
      await setShowOverride(key!, profile);
    } else {
      await setGlobalDefaults(profile);
    }
  }
}

/// Tags a YouTube episode with the show it was opened from, so it plays
/// with that show's playback settings. Items that already know their show
/// are returned unchanged.
MediaItem withPodcastShowId(MediaItem item, String? playlistId) {
  if (playlistId == null || playlistId.isEmpty) return item;
  final extras = item.extras ?? const <String, dynamic>{};
  if (extras['podcastPlaylistId'] != null || extras['feedUrl'] != null) {
    return item;
  }
  return item.copyWith(
      extras: {...extras, 'podcastPlaylistId': playlistId});
}
