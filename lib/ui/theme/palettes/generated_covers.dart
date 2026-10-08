import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// One colour scheme for a generated playlist cover: a deep [base] the
/// blobs sit on, two vivid colours that flow into each other ([primary],
/// [secondary]) and a lighter [highlight] that glows inside [secondary]
/// (a tint of it, or a hue that blends with it cleanly).
@immutable
class GeneratedCoverPalette {
  const GeneratedCoverPalette({
    required this.base,
    required this.primary,
    required this.secondary,
    required this.highlight,
  });

  final Color base;
  final Color primary;
  final Color secondary;
  final Color highlight;
}

/// Curated colour schemes for playlists without artwork (content identity,
/// not UI chrome). A playlist's id picks one, so it is stable: append new
/// schemes at the end only, and never reorder, or existing playlists change
/// colour. Every scheme keeps white title text readable.
class GeneratedCoverPalettes {
  GeneratedCoverPalettes._();

  static const List<GeneratedCoverPalette> all = [
    // Purple / coral.
    GeneratedCoverPalette(
      base: Color(0xFF3A0B86),
      primary: Color(0xFF7B1FD0),
      secondary: Color(0xFFFF7A59),
      highlight: Color(0xFFFFB38A),
    ),
    // Blue / teal.
    GeneratedCoverPalette(
      base: Color(0xFF0A1F6B),
      primary: Color(0xFF1F5BFF),
      secondary: Color(0xFF0FBFAE),
      highlight: Color(0xFF7FEFD9),
    ),
    // Magenta / orange.
    GeneratedCoverPalette(
      base: Color(0xFF6B0844),
      primary: Color(0xFFD81B7D),
      secondary: Color(0xFFFF8A1F),
      highlight: Color(0xFFFFC46B),
    ),
    // Green / yellow.
    GeneratedCoverPalette(
      base: Color(0xFF07482A),
      primary: Color(0xFF13A05A),
      secondary: Color(0xFFD9E021),
      highlight: Color(0xFFF1F78A),
    ),
    // Indigo / pink.
    GeneratedCoverPalette(
      base: Color(0xFF1C1366),
      primary: Color(0xFF4B3BDB),
      secondary: Color(0xFFFF5FA2),
      highlight: Color(0xFFFFA6CB),
    ),
    // Crimson / gold.
    GeneratedCoverPalette(
      base: Color(0xFF5C0716),
      primary: Color(0xFFD0233C),
      secondary: Color(0xFFFFA62B),
      highlight: Color(0xFFFFD27A),
    ),
    // Deep teal / lime.
    GeneratedCoverPalette(
      base: Color(0xFF06343F),
      primary: Color(0xFF0E7C86),
      secondary: Color(0xFFA6E34B),
      highlight: Color(0xFFE2F97A),
    ),
    // Violet / cyan.
    GeneratedCoverPalette(
      base: Color(0xFF26086B),
      primary: Color(0xFF8A2BE2),
      secondary: Color(0xFF1CC8E8),
      highlight: Color(0xFF9DF3FF),
    ),
    // Sunset: red / amber, a pink glow.
    GeneratedCoverPalette(
      base: Color(0xFF6E1020),
      primary: Color(0xFFF0433A),
      secondary: Color(0xFFFFB03A),
      highlight: Color(0xFFFF8FB1),
    ),
    // Hot pink / peach.
    GeneratedCoverPalette(
      base: Color(0xFF6E1240),
      primary: Color(0xFFFF4F8B),
      secondary: Color(0xFFFF9A3D),
      highlight: Color(0xFFFFC27A),
    ),
    // Rose / lavender.
    GeneratedCoverPalette(
      base: Color(0xFF5E0B34),
      primary: Color(0xFFD12F7A),
      secondary: Color(0xFF8B6CF5),
      highlight: Color(0xFFCDB9FF),
    ),
    // Sky / violet.
    GeneratedCoverPalette(
      base: Color(0xFF10226B),
      primary: Color(0xFF2F8FF0),
      secondary: Color(0xFF8F4FF2),
      highlight: Color(0xFFC9A6FF),
    ),
    // Cherry / violet.
    GeneratedCoverPalette(
      base: Color(0xFF4A0630),
      primary: Color(0xFFE11D48),
      secondary: Color(0xFF8B5CF6),
      highlight: Color(0xFFC4A5FF),
    ),
    // Peach / lilac.
    GeneratedCoverPalette(
      base: Color(0xFF4C1D95),
      primary: Color(0xFFF2704E),
      secondary: Color(0xFF8E5CF0),
      highlight: Color(0xFFD5B8FF),
    ),
    // Electric blue / magenta.
    GeneratedCoverPalette(
      base: Color(0xFF0F1A6E),
      primary: Color(0xFF3355FF),
      secondary: Color(0xFFE6399B),
      highlight: Color(0xFFFF9AD5),
    ),
    // Berry / tangerine.
    GeneratedCoverPalette(
      base: Color(0xFF4A0A2A),
      primary: Color(0xFFB0185E),
      secondary: Color(0xFFFF7A1A),
      highlight: Color(0xFFFFB86B),
    ),
  ];

  /// Light and dark film-grain specks drawn over every cover.
  static const Color grainLight = Color(0xFFFFFFFF);
  static const Color grainDark = Color(0xFF000000);

  /// Darkening behind the title along the bottom.
  static const Color titleShade = Color(0xFF000000);
}
