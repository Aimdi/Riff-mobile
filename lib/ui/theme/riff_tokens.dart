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

  /// Pulse ring behind the listen button.
  static const double recognizeRingOpacity = 0.2;

  /// Podcast folder tile without a photo: the colour's tint behind the
  /// folder icon, and its hairline edge.
  static const double folderTint = 0.22;
  static const double folderEdge = 0.55;

  /// Active rail item: accent fill and outline strengths.
  static const double railActiveFillOpacity = 0.16;
  static const double railActiveBorderOpacity = 0.28;

  /// Most any album-art or colour layer may show through the full-player
  /// background (CLAUDE.md rule 4: ≤ 20% over black).
  static const double playerTintOpacity = 0.2;

  /// Scrim behind the player's "Playing from" header over the cover: dark
  /// at the very top, half that where the header text ends, so it stays
  /// readable on light covers.
  static const double playerHeaderScrim = 0.75;
  static const double playerHeaderScrimMid = 0.45;

  /// Lyrics lines other than the current one (secondary text at 60%).
  static const double lyricsDimOpacity = 0.6;

  /// Riff Wave card cover: the accent tint shown when there is no cover
  /// yet, and the scrim under the waveform (keep the current values).
  static const double waveArtTint = 0.22;
  static const double waveArtScrim = 0.4;
}

/// Corner radii (§4.3).
class RiffRadii {
  RiffRadii._();

  static const double xs = 4;
  static const double sm = 8;
  static const double lg = 16;
  static const double pill = 999;

  /// Floating mini-player card corners (keeps its current shape).
  static const double miniPlayer = 24;
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

  /// "What's playing?" screen: listen button, its pulse ring (box size and
  /// growth at full mic level), glyph and the result cover.
  static const double recognizeButton = 120;
  static const double recognizeRingScale = 1.6;
  static const double recognizeRingGrow = 0.6;
  static const double recognizeGlyph = 48;
  static const double recognizeCover = 200;

  /// Side rail, pre-restyle look (kept by request): 22 dp glyph in an
  /// 8 dp-padded box (Songs children: 18 in 6), radius 12 with a 0.5 dp
  /// outline when active, 6 dp to the rotated label, 14 dp press shape.
  static const double railGlyph = 22;
  static const double railSubGlyph = 18;
  static const double railSubPillPadding = 6;
  static const double railPillRadius = 12;
  static const double railPillBorder = 0.5;
  static const double railLabelGap = 6;
  static const double railItemRadius = 14;

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

  /// Skip-ad pill glyph, and how far the pill slides up as it appears.
  static const double skipPillIcon = 16;
  static const double skipPillSlide = 8;

  /// Full-player seek bar: track height and the thumb shown while dragging.
  static const double seekTrack = 2;
  static const double seekThumb = 12;

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

  /// Mini player (§5 Phase 6): play/pause and skip glyphs, the fixed hit
  /// widths of the skip buttons and play/pause (keep the current sizes), the
  /// height of each text line, the playback-error glyph and the thin
  /// progress line along the card's bottom edge.
  static const double miniPlayIcon = 28;
  static const double miniNextIcon = 24;
  static const double miniSkipHit = 28;
  static const double miniPlayHit = 38;
  static const double miniLine = 20;
  static const double miniErrorIcon = 14;
  static const double miniProgress = 2;

  /// The full player's collapsed "Up Next" tab: its height above the
  /// system inset (it runs down to the screen edge), and the widest it gets
  /// (tablets; the player controls column is as wide).
  static const double queueCard = 30;
  static const double queueCardMaxWidth = 500;

  /// Wide (desktop) mini player: skip glyphs, their hit widths, the
  /// accent play circle and its glyph (keep the current sizes), and the
  /// seek-bar thumb (§5 Phase 6: 12 across).
  static const double miniWideSkipIcon = 35;
  static const double miniWideSkipHit = 40;
  static const double miniWidePlay = 58;
  static const double miniWidePlayIcon = 30;
  static const double miniWideThumb = 6;

  /// Thin progress line on episode / audiobook rows and covers
  /// (§ Phase 7: 2 px accent on a divider track).
  static const double rowProgress = 2;

  /// Long-form (podcast / audiobook) player, keeping the current sizes: the
  /// accent play circle, the skip-seconds glyphs, the previous / next
  /// glyphs and the cover's fallback glyph.
  static const double longFormPlay = 76;
  static const double longFormSkip = 38;
  static const double longFormEdge = 30;
  static const double longFormFallbackIcon = 72;

  /// Outline chips with a leading glyph and / or a trailing chevron (the
  /// long-form player's chapter chip, the Audiobookshelf library picker),
  /// keeping the current sizes.
  static const double chipLeadingIcon = 16;
  static const double chipChevron = 18;

  /// Audiobook headers, keeping the current sizes: the Audiobookshelf
  /// book's 2:3 cover (also the "Similar titles" cards), the square store
  /// cover, and the chapter-number circle on Audiobookshelf chapter rows.
  static const double bookCoverWidth = 120;
  static const double bookCoverHeight = 180;
  static const double storeBookCover = 200;
  static const double chapterNumber = 32;

  /// Circular spinner (§5.9: 24 across, stroke 2.5).
  static const double spinner = 24;
  static const double spinnerStroke = 2.5;

  /// Podcasts, keeping the current sizes: the show page cover's min / max
  /// side, the Continue listening card's art and its play badge (+ glyph),
  /// the show-search result art, the "Expected today" card (width and row
  /// height), the YouTube video-episode card width, the Subscriptions
  /// cover's play button, the folder glyph and the empty-state glyph.
  static const double showCoverMin = 160;
  static const double showCoverMax = 240;
  static const double continueArt = 64;
  static const double continueBadge = 24;
  static const double continueBadgeIcon = 18;
  static const double showRowArt = 72;
  static const double expectedCardWidth = 230;
  static const double expectedRowHeight = 64;
  static const double videoEpisodeWidth = 256;
  static const double coverPlay = 30;
  static const double folderIcon = 64;

  /// Podcast folder photo: the frame in the folder colour around it.
  static const double folderPhotoFrame = 6;
  static const double emptyStateIcon = 56;

  /// Settings (Phase 8): a settings row's minimum height (§5.9 / Phase 8),
  /// the glyph box on a settings group header, small inline glyphs (status
  /// marks, the accent swatch tick), the accent swatches, the error-state
  /// glyph on sign-in screens and the rows of Home layout — all keeping
  /// their current sizes.
  static const double settingsRow = 52;
  static const double settingsGroupIcon = 38;
  static const double inlineIcon = 18;
  static const double accentSwatch = 32;
  static const double errorStateIcon = 40;
  static const double homeLayoutRow = 56;

  /// Settings dialogs' fixed heights (keep the current sizes): the radio
  /// choice dialogs and their scrolling list, Discovery settings and the
  /// taste-model debug dialog.
  static const double choiceDialog = 300;
  static const double choiceDialogList = 180;
  static const double discoveryDialog = 460;
  static const double tasteDebugDialog = 480;

  /// Stats, Podcast stats and Rewind (keep the current sizes): stat-tile
  /// glyph, the last-7-days chart height, rank columns (wide / compact),
  /// the top-show artwork, the small brand glyph on the share card, the
  /// Rewind listener-level circle and its stat tiles.
  static const double statIcon = 20;
  static const double statsChart = 150;
  static const double statsRank = 30;
  static const double statsRankCompact = 22;
  static const double statsShowArt = 44;
  static const double brandGlyph = 14;
  static const double rewindLevel = 84;
  static const double rewindStat = 104;

  /// Sheets and menus (§5.10): a row's minimum height and its leading
  /// icon, and the glyph of a sheet's big quick-action tiles (keeps its
  /// current size).
  static const double sheetRow = 52;
  static const double sheetIcon = 22;
  static const double sheetQuickIcon = 24;

  /// Widest a bottom sheet gets on tablets (the song sheet's width).
  static const double sheetMaxWidth = 500;

  /// Artwork in the song sheet's header (keeps its current size).
  static const double sheetHeaderArt = 56;

  /// Dialog heading's icon badge and its glyph (keep their current size).
  static const double dialogBadge = 52;
  static const double dialogBadgeIcon = 26;

  /// Width of the copy action at the end of a split dialog option (keeps
  /// its current size).
  static const double splitAction = 56;

  /// Spinner inside a button's icon slot (keeps its current size).
  static const double buttonSpinner = 16;
}

/// Generated covers for playlists without artwork (colours in
/// palettes/generated_covers.dart).
class RiffCoverArt {
  RiffCoverArt._();

  /// Smaller covers show only the colour blobs: list rows and the 96 dp
  /// collection header already print the title next to the art.
  static const double titleMinSize = 100;

  /// The title is laid out on a cover this big, then scaled with the cover,
  /// so it wraps the same way at every size.
  static const double titleDesignSize = 160;

  /// Title lines: the large style, then the compact one for long titles.
  static const int titleMaxLines = 2;
  static const int titleMaxLinesCompact = 3;

  /// Blur of the colour blobs, as a share of the cover's side.
  static const double blobBlur = 0.17;

  /// Film grain: side of the repeating noise tile (px), share of its pixels
  /// that get a speck, and the specks' strength.
  static const int grainTile = 128;
  static const double grainDensity = 0.55;
  static const double grainLightOpacity = 0.06;
  static const double grainDarkOpacity = 0.09;

  /// Shade behind the title: its strength at the bottom edge, and how far
  /// up the cover it reaches (share of the side).
  static const double titleShadeOpacity = 0.36;
  static const double titleShadeExtent = 0.6;

  /// Raster sizes (physical px) a cover is drawn at: the smallest one at
  /// least as big as the cover on screen, so a few sizes serve every list.
  static const List<int> rasterSizes = [96, 160, 256, 384, 512, 768, 1024];

  /// Most memory the drawn covers may keep (bytes); older ones are dropped
  /// and drawn again when they scroll back in.
  static const int cacheBytes = 24 * 1024 * 1024;
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
