import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The most Riff enlarges text when the phone's font size asks for more:
/// Android's largest size before Android 14 ("Largest", 1.3x). Up to it
/// the players, rows and sheets make room; past it they would run out of
/// it on a phone.
const double kRiffMaxTextScale = 1.3;

/// The phone's font size as Riff applies it: larger up to
/// [kRiffMaxTextScale], never smaller than the default.
TextScaler riffTextScaler(TextScaler system) =>
    system.clamp(minScaleFactor: 1.0, maxScaleFactor: kRiffMaxTextScale);

/// Height of one line of [style] at the user's text size. Fixed-height
/// rows and shelves size themselves from the same TextTheme slot their
/// text uses, so a theme change can't make them overflow.
double riffLineHeight(BuildContext context, TextStyle? style,
    {double fallbackHeight = 1.2}) {
  final size = style?.fontSize ?? 14;
  // Rounded up: text layout can land a hair above size × height.
  return (MediaQuery.textScalerOf(context).scale(size) *
          (style?.height ?? fallbackHeight))
      .ceilToDouble();
}

/// A line's fixed box: [min] tall, as designed for the default text size,
/// or [style]'s line once a larger font size makes it taller, so the text
/// isn't cut off.
double riffLineBox(BuildContext context, TextStyle? style, double min) =>
    math.max(min, riffLineHeight(context, style));
