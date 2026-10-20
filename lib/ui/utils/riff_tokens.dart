import 'package:flutter/material.dart';

/// Shared layout tokens for the Riff daily-loop UI (motion lives in
/// RiffDurations).
/// Prefer these over one-off magic numbers in new surfaces.
class RiffTokens {
  RiffTokens._();

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double hairline = 0.5;

  static BorderSide hairlineBorder(BuildContext context) {
    final c = Theme.of(context).dividerColor;
    return BorderSide(color: c.withOpacity(0.85), width: hairline);
  }
}
