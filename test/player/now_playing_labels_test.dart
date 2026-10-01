import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/ui/player/components/player_control.dart';
import 'package:harmonymusic/ui/player/components/standard_player.dart';

void main() {
  group('speedLabel', () {
    test('drops trailing zeros', () {
      expect(speedLabel(1.0), '1×');
      expect(speedLabel(1.5), '1.5×');
      expect(speedLabel(1.75), '1.75×');
      expect(speedLabel(0.8), '0.8×');
      expect(speedLabel(2.0), '2×');
    });
  });

  group('sleepTimerBadge', () {
    test('rounds up to the largest unit', () {
      expect(sleepTimerBadge(45), '45s');
      expect(sleepTimerBadge(60), '1m');
      expect(sleepTimerBadge(61), '2m');
      expect(sleepTimerBadge(1500), '25m');
      expect(sleepTimerBadge(3600), '1h');
      expect(sleepTimerBadge(5400), '2h');
    });

    test('empty when nothing is left', () {
      expect(sleepTimerBadge(0), '');
      expect(sleepTimerBadge(-3), '');
    });
  });

  group('playingFromLabel', () {
    test('splits kind and name', () {
      final label = playingFromLabel(
          PlaylingFrom(type: PlaylingFromType.PLAYLIST, name: 'Road trip'));
      expect(label, isNotNull);
      expect(label!.name, 'Road trip');
      expect(label.type, isNotEmpty);
    });

    test('album without a name keeps only the kind', () {
      final label =
          playingFromLabel(PlaylingFrom(type: PlaylingFromType.ALBUM));
      expect(label, isNotNull);
      expect(label!.name, '');
    });
  });
}
