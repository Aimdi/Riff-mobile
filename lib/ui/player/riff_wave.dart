import 'package:audio_service/audio_service.dart';

/// Pure helpers for Home "Riff Wave" personal radio.
class RiffWave {
  const RiffWave._();

  /// Pick a seed video id source, strongest signal first.
  ///
  /// When [preferTasteSeed] is true (Home Wave hero), skip the currently
  /// playing track so Wave stays taste-based rather than "radio of whatever
  /// happens to be on." In-player radio should keep [preferTasteSeed] false.
  static MediaItem? resolveSeed({
    MediaItem? currentSong,
    MediaItem? dailyMixSeed,
    MediaItem? quickPick,
    MediaItem? mostRecent,
    String? recentSongId,
    bool preferTasteSeed = false,
  }) {
    if (!preferTasteSeed &&
        currentSong != null &&
        currentSong.id.isNotEmpty) {
      return currentSong;
    }
    if (dailyMixSeed != null && dailyMixSeed.id.isNotEmpty) return dailyMixSeed;
    if (quickPick != null && quickPick.id.isNotEmpty) return quickPick;
    if (mostRecent != null && mostRecent.id.isNotEmpty) return mostRecent;
    if (recentSongId != null && recentSongId.isNotEmpty) {
      return MediaItem(id: recentSongId, title: 'Wave');
    }
    if (preferTasteSeed &&
        currentSong != null &&
        currentSong.id.isNotEmpty) {
      return currentSong;
    }
    return null;
  }

  /// Ensure [seed] leads the radio queue when present.
  static List<MediaItem> withSeedFirst(
    List<MediaItem> tracks,
    MediaItem? seed,
  ) {
    if (seed == null || seed.id.isEmpty) {
      return List<MediaItem>.from(tracks);
    }
    return [
      seed,
      ...tracks.where((t) => t.id != seed.id),
    ];
  }
}
