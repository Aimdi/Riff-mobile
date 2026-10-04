import 'package:flutter/material.dart';

/// Design tokens for the "X Lights out, Riff green" look
/// (RIFF_UI_RESTYLE.md §4). Widgets read colours through
/// `Theme.of(context).colorScheme` / [RiffColors]; these constants exist for
/// the theme itself and for the few places that build the theme's pieces.

/// Colours (§4.1). The accent is the user's choice and lives in the theme.
class RiffPalette {
  RiffPalette._();

  static const Color bg = Color(0xFF000000);
  static const Color surface1 = Color(0xFF16181C);
  static const Color surface2 = Color(0xFF202327);
  static const Color divider = Color(0xFF2F3336);
  static const Color outlineStrong = Color(0xFF536471);
  static const Color textPrimary = Color(0xFFE7E9EA);
  static const Color textSecondary = Color(0xFF71767B);
  static const Color onAccent = Color(0xFF000000);
  static const Color handle = Color(0xFF333639);
  static const Color barrier = Color(0x665B7083); // #5B7083 @ 40%
  static const Color danger = Color(0xFFF4212E);

  /// Text and icons drawn over artwork or a scrim: white in every theme.
  static const Color onImage = Color(0xFFFFFFFF);

  /// Darkening layers over artwork, and shadows.
  static const Color scrim = Color(0xFF000000);

  /// The accent at 12% over black: selected chips, now-playing rows.
  static Color accentMuted(Color accent) =>
      Color.alphaBlend(accent.withOpacity(0.12), bg);
}

/// Corner radii (§4.3).
class RiffRadii {
  RiffRadii._();

  static const double xs = 4;
  static const double sm = 8;
  static const double lg = 16;
  static const double pill = 999;
}

/// Motion (§4.7).
class RiffDurations {
  RiffDurations._();

  static const Duration press = Duration(milliseconds: 100);
  static const Duration select = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 250);
  static const Duration page = Duration(milliseconds: 250);
  static const Curve selectCurve = Curves.easeOutCubic;
}

/// Component sizes from §4.4 that aren't Home-specific ([RiffSizes] in
/// home_metrics.dart keeps the Home ones).
class RiffComponentSizes {
  RiffComponentSizes._();

  static const double rowArt = 48;
  static const double miniArt = 40;
  static const double headerIcon = 22;
  static const double trailingIcon = 20;
  static const double railIcon = 24;
  static const double iconHit = 40;
  static const double buttonCompact = 36;
  static const double button = 40;
  static const double chip = 32;
  static const double searchField = 40;
  static const double handleWidth = 36;
  static const double handleHeight = 4;
  static const double skipPill = 36;
}

/// Theme-dependent colours Material's [ColorScheme] has no slot for.
@immutable
class RiffColors extends ThemeExtension<RiffColors> {
  const RiffColors({
    required this.accentMuted,
    required this.handle,
    required this.barrier,
    required this.surface2,
    this.onImage = RiffPalette.onImage,
    this.scrim = RiffPalette.scrim,
  });

  final Color accentMuted;
  final Color handle;
  final Color barrier;
  final Color surface2;

  /// Text and icons over artwork or a scrim (white in every theme). For
  /// dimmer text use `onImage.withOpacity(...)`.
  final Color onImage;

  /// Darkening layers over artwork, and shadows (use with opacity).
  final Color scrim;

  factory RiffColors.forAccent(Color accent) => RiffColors(
        accentMuted: RiffPalette.accentMuted(accent),
        handle: RiffPalette.handle,
        barrier: RiffPalette.barrier,
        surface2: RiffPalette.surface2,
      );

  /// The theme's [RiffColors], or Lights-out defaults for themes that don't
  /// carry one (light, album colour).
  static RiffColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<RiffColors>() ??
        RiffColors.forAccent(theme.colorScheme.secondary);
  }

  @override
  RiffColors copyWith({
    Color? accentMuted,
    Color? handle,
    Color? barrier,
    Color? surface2,
    Color? onImage,
    Color? scrim,
  }) =>
      RiffColors(
        accentMuted: accentMuted ?? this.accentMuted,
        handle: handle ?? this.handle,
        barrier: barrier ?? this.barrier,
        surface2: surface2 ?? this.surface2,
        onImage: onImage ?? this.onImage,
        scrim: scrim ?? this.scrim,
      );

  @override
  RiffColors lerp(ThemeExtension<RiffColors>? other, double t) {
    if (other is! RiffColors) return this;
    return RiffColors(
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      handle: Color.lerp(handle, other.handle, t)!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      onImage: Color.lerp(onImage, other.onImage, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}
