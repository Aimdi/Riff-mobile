import 'package:flutter/material.dart';

import '../../utils/riff_tokens.dart';
import '../../utils/theme_controller.dart';

/// Spotify-style Home title from the local clock.
String homeGreetingKey(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return 'goodMorning';
  if (hour < 17) return 'goodAfternoon';
  return 'goodEvening';
}

/// Status-bar inset plus a small gap — not an 80px empty band.
double homeFeedTopPadding({
  required bool isDesktop,
  required bool isLandscape,
  required double statusBar,
}) {
  if (isDesktop) return 85;
  if (isLandscape) return statusBar + 8;
  return statusBar + 12;
}

double homeGreetingFontSize({required bool isDesktop}) =>
    isDesktop ? 32 : RiffTokens.homeGreetingSize;

/// Spotify Home shows up to six recents in a 2-column grid.
int jumpBackInGridCount(int available, {int max = 6}) {
  if (available <= 0) return 0;
  return available < max ? available : max;
}

double discoveryShelfCardSize({required bool isDailyMix}) =>
    isDailyMix ? 148 : 136;

double discoveryShelfRowHeight({required bool isDailyMix}) =>
    isDailyMix ? 200 : 186;

TextStyle homeSectionTitleStyle(TextTheme theme) {
  return (theme.titleLarge ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w800,
    fontSize: RiffTokens.homeSectionSize,
    letterSpacing: -0.55,
    height: 1.15,
  );
}

Color homeTileFill(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? RiffSurfaces.elevatedSoft
      : theme.cardColor;
}
