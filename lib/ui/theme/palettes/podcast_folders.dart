import 'package:flutter/painting.dart';

/// Preset podcast folder colours (Spotify-style chips). This is a data
/// palette: the user picks one per folder and its index is persisted with
/// the folder, so the order must never change.
class PodcastFolderColors {
  PodcastFolderColors._();

  static const List<Color> swatches = [
    Color(0xFF1DB954), // green
    Color(0xFF1E90FF), // dodger blue
    Color(0xFF9B59B6), // purple
    Color(0xFFE74C3C), // red
    Color(0xFFF39C12), // amber
    Color(0xFF1ABC9C), // teal
    Color(0xFFE91E63), // pink
    Color(0xFF00BCD4), // cyan
    Color(0xFFFF5722), // deep orange
    Color(0xFF8BC34A), // light green
    Color(0xFF607D8B), // blue grey
    Color(0xFF795548), // brown
  ];

  static Color of(int index) => swatches[index.clamp(0, swatches.length - 1)];
}
