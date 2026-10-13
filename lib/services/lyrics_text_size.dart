/// Lyrics text size (Settings › Lyrics text size), as in Metrolist: how big
/// lyrics are drawn, on top of the phone's own font size.
library;

import 'package:flutter/painting.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

enum LyricsTextSize {
  small(0.85, 'lyricsTextSmall'),
  standard(1.0, 'lyricsTextDefault'),
  large(1.2, 'lyricsTextLarge'),
  largest(1.45, 'lyricsTextLargest');

  const LyricsTextSize(this.factor, this.labelKey);

  /// Times the phone's font size.
  final double factor;
  final String labelKey;

  /// AppPrefs key (the size's name).
  static const key = 'lyricsTextSize';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// The size chosen (Default until one is).
  static final selected = Rx<LyricsTextSize>(_stored());

  static LyricsTextSize _stored() {
    final name = _prefs?.get(key);
    return values.firstWhere((s) => s.name == name, orElse: () => standard);
  }

  static Future<void> set(LyricsTextSize size) async {
    selected.value = size;
    await _prefs?.put(key, size.name);
  }
}

/// [base] (the phone's font size, linear or not) times [factor].
class ScaledTextScaler extends TextScaler {
  const ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(_reference) / _reference;
  static const double _reference = 14;

  @override
  bool operator ==(Object other) =>
      other is ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// [style] at the size [scaler] gives it, for text drawn without a Text
/// widget (the synced lyrics reader paints its lines unscaled).
TextStyle scaledTextStyle(TextStyle style, TextScaler scaler) {
  final size = style.fontSize;
  if (size == null || size <= 0) return style;
  return style.apply(fontSizeFactor: scaler.scale(size) / size);
}
