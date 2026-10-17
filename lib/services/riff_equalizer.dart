/// Riff's own equalizer, like Spotify's: presets and band levels for phones
/// with no equalizer of their own (Pixels, among others). Kept in AppPrefs
/// and applied with the other effects (bass, volume boost, reverb) to the
/// player's audio session; off by default, so the sound doesn't change
/// until it's turned on.
library;

import 'dart:math';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// The phone's equalizer: its bands' centre frequencies and how far each
/// can go, in millibels (1 dB = 100 mB).
class EqualizerLayout {
  const EqualizerLayout(
      {required this.centersHz, required this.minMb, required this.maxMb});

  final List<int> centersHz;
  final int minMb;
  final int maxMb;

  static EqualizerLayout? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final centers = raw['centersHz'];
    final min = raw['minMb'];
    final max = raw['maxMb'];
    if (centers is! List || min is! int || max is! int || min >= max) {
      return null;
    }
    final hz = [
      for (final c in centers)
        if (c is int && c > 0) c
    ];
    if (hz.isEmpty || hz.length != centers.length) return null;
    return EqualizerLayout(centersHz: hz, minMb: min, maxMb: max);
  }
}

/// The frequencies the presets are given at; a phone's bands get the
/// curve between them.
const equalizerPresetHz = [60, 230, 910, 3600, 14000];

/// Spotify's presets, in dB at [equalizerPresetHz]. The keys are the
/// strings' too ('eqPreset<Key>').
const equalizerPresets = <String, List<double>>{
  'flat': [0, 0, 0, 0, 0],
  'bassBooster': [6, 4, 0, 0, 0],
  'bassReducer': [-6, -4, 0, 0, 0],
  'trebleBooster': [0, 0, 0, 4, 6],
  'trebleReducer': [0, 0, 0, -4, -6],
  'vocalBooster': [-2, -1, 4, 3, 0],
  'acoustic': [4, 2, 1, 3, 3],
  'classical': [4, 2, -1, 2, 4],
  'dance': [5, 2, 0, 2, 4],
  'hipHop': [5, 4, 0, 1, 3],
  'jazz': [3, 1, -1, 2, 3],
  'pop': [-1, 2, 4, 2, -1],
  'rock': [5, 3, -1, 3, 5],
  'electronic': [5, 3, 0, 2, 5],
  'spokenWord': [-3, 0, 3, 3, 0],
  'smallSpeakers': [5, 4, 1, 2, 2],
};

/// What [layout]'s bands are set to for a curve of [db] at
/// [equalizerPresetHz]: read off the curve at each band's centre
/// (straight between two points on a log scale, level past the ends), in
/// millibels within the phone's range.
List<int> equalizerLevelsFor(List<double> db, EqualizerLayout layout) {
  final logs = [for (final f in equalizerPresetHz) log(f)];
  double at(int hz) {
    final x = log(hz);
    if (x <= logs.first) return db.first;
    if (x >= logs.last) return db.last;
    var i = 0;
    while (logs[i + 1] < x) {
      i++;
    }
    final t = (x - logs[i]) / (logs[i + 1] - logs[i]);
    return db[i] + (db[i + 1] - db[i]) * t;
  }

  return [
    for (final hz in layout.centersHz)
      (at(hz) * 100).round().clamp(layout.minMb, layout.maxMb)
  ];
}

class RiffEqualizer {
  RiffEqualizer._();

  static const enabledKey = 'eqEnabled';
  static const presetKey = 'eqPreset';
  static const levelsKey = 'eqLevelsMb';

  /// The preset name once the bands are moved by hand.
  static const custom = 'custom';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static bool get enabled => _prefs?.get(enabledKey) == true;

  static String get preset {
    final p = _prefs?.get(presetKey);
    return p is String && (p == custom || equalizerPresets.containsKey(p))
        ? p
        : 'flat';
  }

  /// The levels applied, in millibels per band (lowest band first).
  static List<int> get levelsMb {
    final raw = _prefs?.get(levelsKey);
    return raw is List
        ? [
            for (final v in raw)
              if (v is int) v
          ]
        : const [];
  }

  static Future<void> save(
      {bool? enabled, String? preset, List<int>? levelsMb}) async {
    final b = _prefs;
    if (b == null) return;
    if (enabled != null) await b.put(enabledKey, enabled);
    if (preset != null) await b.put(presetKey, preset);
    if (levelsMb != null) await b.put(levelsKey, levelsMb);
    rev.value++;
  }
}
