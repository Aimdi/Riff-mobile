/// Spacing and Home component sizes (RIFF_UI_RESTYLE.md §4.2, §4.4).
/// Every padding, gap and margin in widget code comes from [RiffSpacing].
library;

/// Spacing scale. Everything lines up 16dp from the rail.
class RiffSpacing {
  RiffSpacing._();

  // The 4-point scale (RIFF_UI_RESTYLE.md §4.2).
  static const double unit = 4;
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3l = 32;

  /// Room left under scrolling lists for the mini player (and its
  /// shadow) on screens that don't compute it.
  static const double listEnd = 200;

  /// Content margin from the rail's edge and from the right edge.
  static const double gutter = 16;

  /// Space above every section.
  static const double section = x3l;

  /// Height of a section's title row.
  static const double headerRow = 48;

  /// Title row to content.
  static const double headerToContent = md;

  /// Between cards on a shelf.
  static const double cardGap = 12;

  /// Inside grids (Jump back in, Speed dial).
  static const double gridGap = 8;

  /// Riff Wave card to its chip row.
  static const double chipRowTop = 12;

  /// Bottom margin of the app's snackbars, so they float above the mini
  /// player (keeps the current offset).
  static const double snackbarBottom = 100;
}

/// Home component sizes and corner radii.
class RiffSizes {
  RiffSizes._();

  static const double tileRadius = 8;
  static const double shelfRadius = 8;
  static const double waveRadius = 16;
  static const double carouselRadius = 8;

  static const double jumpTileHeight = 56;
  static const double jumpArt = 48;
  static const double progressBar = 3;

  static const double waveHeight = 88;
  static const double waveArt = 56;
  static const double wavePlay = 48;
  static const double chipRow = 48;
  static const double chipHeight = 32;
  static const double chipIcon = 24;
  static const double chipGlyph = 14;

  static const double dot = 6;
  static const double dotsTop = 8;

  static const double carouselHeight = 200;
  static const double carouselPeek = 48;
  static const double carouselSpacing = 8;
  static const double carouselPlay = 40;

  static const double artistCircle = 112;
  static const double videoWidth = 224;
  static const double episodeWidth = 280;
  static const double weekHeight = 96;
  static const double touch = 48;
}
