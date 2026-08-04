import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/abs_progress.dart';

void main() {
  group('mapAbsCurrentTimeToTrack', () {
    test('empty tracks → index 0', () {
      final r = mapAbsCurrentTimeToTrack(90, const []);
      expect(r.$1, 0);
      expect(r.$2, Duration.zero);
    });

    test('maps into first track', () {
      final r = mapAbsCurrentTimeToTrack(45, const [100.0, 200.0]);
      expect(r.$1, 0);
      expect(r.$2, const Duration(seconds: 45));
    });

    test('maps into second track', () {
      final r = mapAbsCurrentTimeToTrack(150, const [100.0, 200.0]);
      expect(r.$1, 1);
      expect(r.$2, const Duration(seconds: 50));
    });

    test('clamps past end onto last track', () {
      final r = mapAbsCurrentTimeToTrack(9999, const [100.0, 50.0]);
      expect(r.$1, 1);
      expect(r.$2, const Duration(seconds: 50));
    });
  });

  group('parseAbsProgress', () {
    test('reads userMediaProgress.progress', () {
      expect(
        parseAbsProgress({
          'userMediaProgress': {'progress': 0.42},
        }),
        closeTo(0.42, 0.001),
      );
    });

    test('reads progressPercentage as percent', () {
      expect(
        parseAbsProgress({
          'media': {'progressPercentage': 75},
        }),
        closeTo(0.75, 0.001),
      );
    });
  });
}
