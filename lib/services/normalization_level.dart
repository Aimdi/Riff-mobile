/// Loudness normalization's volume level (Settings, under Loudness
/// normalization), like Spotify's Quiet / Normal / Loud: how loud songs are
/// all brought to.
library;

import 'dart:math';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

enum NormalizationLevel {
  quiet(-10, 'normalizationQuiet'),
  normal(-5, 'normalizationNormal'),
  loud(0, 'normalizationLoud');

  const NormalizationLevel(this.targetDb, this.labelKey);

  /// The loudness songs are brought to, in dB against YouTube's reference
  /// (Normal is what normalization always used).
  final double targetDb;
  final String labelKey;

  /// AppPrefs key (the level's name).
  static const key = 'normalizationLevel';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static final selected = Rx<NormalizationLevel>(_stored());

  static NormalizationLevel _stored() {
    final name = _prefs?.get(key);
    return values.firstWhere((l) => l.name == name, orElse: () => normal);
  }

  static Future<void> set(NormalizationLevel level) async {
    selected.value = level;
    await _prefs?.put(key, level.name);
  }
}

/// The volume (0–1) that brings a song [loudnessDb] above YouTube's
/// reference to [targetDb]. Songs quieter than that can't be raised past
/// full volume.
double normalizedVolume(double loudnessDb, double targetDb) =>
    pow(10, (targetDb - loudnessDb) / 20).toDouble().clamp(0.0, 1.0);
