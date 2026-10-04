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
      Color.alphaBlend(accent.withOpacity(accentMutedOpacity), bg);

  /// Accent share in [accentMuted].
  static const double accentMutedOpacity = 0.12;
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

  /// Page-header hairline fading in/out as content scrolls under it.
  static const Duration headerHairline = Duration(milliseconds: 200);

  /// One full loading-skeleton opacity pulse, 0.5 → 1.0 → 0.5 (§5.13).
  static const Duration skeletonPulse = Duration(milliseconds: 1200);
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

  /// Album / playlist header artwork (§5 Phase 5; keeps the current size).
  static const double collectionArt = 96;

  /// Round accent Play on album / playlist / artist headers and its glyph
  /// (keep their current size).
  static const double collectionPlay = 52;
  static const double collectionPlayIcon = 32;

  /// Songs accordion children (Playlists / Albums / Artists).
  static const double railSubIcon = 20;

  /// Circular press highlight behind a rail glyph.
  static const double railHighlight = 40;
  static const double iconHit = 40;

  /// Tab indicator bar height (§5.7).
  static const double tabIndicator = 4;

  /// Hairline under a tab strip. (A TabBar divider can't be 0 = one
  /// physical pixel like a Divider, so half a logical pixel.)
  static const double tabDivider = 0.5;
  static const double buttonCompact = 36;
  static const double button = 40;
  static const double chip = 32;
  static const double searchField = 40;
  static const double handleWidth = 36;
  static const double handleHeight = 4;
  static const double skipPill = 36;

  /// Compact hit box of a list row's trailing icons (heart, ⋮), so they fit
  /// the 48dp row content height.
  static const double rowIconHit = 32;

  /// Play badge glyph over row / wide-tile artwork (keeps its current size).
  static const double artPlayBadge = 22;

  /// Fixed list extents (keep the current sizes): song rows, wide
  /// album/playlist rows (and their artwork), artist rows.
  static const double songRowExtent = 75;
  static const double wideRowExtent = 96;
  static const double wideRowArt = 76;
  static const double artistRowExtent = 72;
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
    final own = theme.extension<RiffColors>();
    if (own != null) return own;
    // Tint over the theme's own surface (white on the light theme).
    final accent = theme.colorScheme.secondary;
    return RiffColors.forAccent(accent).copyWith(
        accentMuted: Color.alphaBlend(
            accent.withOpacity(RiffPalette.accentMutedOpacity),
            theme.colorScheme.surface));
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
