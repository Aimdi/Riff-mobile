import 'package:audio_service/audio_service.dart';

/// Pure helpers for Home "Riff Wave" personal radio.
class RiffWave {
  const RiffWave._();

  /// Pick a seed video id source, strongest signal first.
  static MediaItem? resolveSeed({
    MediaItem? currentSong,
    MediaItem? dailyMixSeed,
    MediaItem? quickPick,
    MediaItem? mostRecent,
    String? recentSongId,
  }) {
    if (currentSong != null && currentSong.id.isNotEmpty) return currentSong;
    if (dailyMixSeed != null && dailyMixSeed.id.isNotEmpty) return dailyMixSeed;
    if (quickPick != null && quickPick.id.isNotEmpty) return quickPick;
    if (mostRecent != null && mostRecent.id.isNotEmpty) return mostRecent;
    if (recentSongId != null && recentSongId.isNotEmpty) {
      return MediaItem(id: recentSongId, title: 'Wave');
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
