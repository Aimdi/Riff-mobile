import 'package:flutter/painting.dart';

/// Audiobook "Browse by genre" tile colours. This is a data palette: each
/// genre tile picks a colour by its position, so the order must not change.
class AudiobookGenrePalette {
  AudiobookGenrePalette._();

  static const List<Color> tiles = [
    Color(0xFF1E3264),
    Color(0xFF8D67AB),
    Color(0xFFE13300),
    Color(0xFF148A08),
    Color(0xFF503750),
    Color(0xFF8C1932),
    Color(0xFF0D73EC),
    Color(0xFFBA5D07),
    Color(0xFF477D95),
    Color(0xFF27856A),
  ];
}
