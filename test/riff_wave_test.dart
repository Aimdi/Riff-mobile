import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/riff_wave.dart';

void main() {
  group('RiffWave.resolveSeed', () {
    test('prefers current song over everything else', () {
      final seed = RiffWave.resolveSeed(
        currentSong: const MediaItem(id: 'a', title: 'Now'),
        dailyMixSeed: const MediaItem(id: 'b', title: 'Mix'),
        quickPick: const MediaItem(id: 'c', title: 'QP'),
        mostRecent: const MediaItem(id: 'd', title: 'Recent'),
        recentSongId: 'e',
      );
      expect(seed?.id, 'a');
    });

    test('falls back through mix → quick pick → stats → prefs id', () {
      expect(
        RiffWave.resolveSeed(
          dailyMixSeed: const MediaItem(id: 'b', title: 'Mix'),
          quickPick: const MediaItem(id: 'c', title: 'QP'),
        )?.id,
        'b',
      );
      expect(
        RiffWave.resolveSeed(
          quickPick: const MediaItem(id: 'c', title: 'QP'),
          mostRecent: const MediaItem(id: 'd', title: 'Recent'),
        )?.id,
        'c',
      );
      expect(
        RiffWave.resolveSeed(
          mostRecent: const MediaItem(id: 'd', title: 'Recent'),
          recentSongId: 'e',
        )?.id,
        'd',
      );
      expect(
        RiffWave.resolveSeed(recentSongId: 'e')?.id,
        'e',
      );
    });

    test('returns null when no signal exists', () {
      expect(RiffWave.resolveSeed(), isNull);
    });
  });

  group('RiffWave.withSeedFirst', () {
    test('prepends seed and dedupes', () {
      final out = RiffWave.withSeedFirst(
        const [
          MediaItem(id: 'x', title: 'X'),
          MediaItem(id: 's', title: 'Old seed'),
          MediaItem(id: 'y', title: 'Y'),
        ],
        const MediaItem(id: 's', title: 'Seed'),
      );
      expect(out.map((e) => e.id).toList(), ['s', 'x', 'y']);
    });
  });
}
