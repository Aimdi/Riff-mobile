import 'package:flutter/material.dart';

/// Shared layout / motion tokens for the Riff daily-loop UI.
/// Prefer these over one-off magic numbers in new surfaces.
class RiffTokens {
  RiffTokens._();

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  /// Album-art corners — tight, like Spotify covers (not pill-soft).
  static const double radiusArt = 6;
  static const double radiusTile = 8;
  static const double homeGreetingSize = 28;
  static const double homeSectionSize = 22;
  static const double hairline = 0.5;

  static const Duration quick = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 260);

  static BorderSide hairlineBorder(BuildContext context) {
    final c = Theme.of(context).dividerColor;
    return BorderSide(color: c.withOpacity(0.85), width: hairline);
  }
}
