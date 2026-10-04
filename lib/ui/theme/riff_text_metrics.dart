import 'package:flutter/widgets.dart';

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
