import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/media_button_presses.dart';

void main() {
  group('what the button does', () {
    test('music: once plays or pauses, twice next, three times previous', () {
      expect(
          mediaButtonAction(1, longForm: false), MediaButtonAction.playPause);
      expect(mediaButtonAction(2, longForm: false), MediaButtonAction.next);
      expect(mediaButtonAction(3, longForm: false), MediaButtonAction.previous);
    });

    test('episodes and books skip forward and back, as their notification does',
        () {
      expect(mediaButtonAction(1, longForm: true), MediaButtonAction.playPause);
      expect(
          mediaButtonAction(2, longForm: true), MediaButtonAction.skipForward);
      expect(mediaButtonAction(3, longForm: true), MediaButtonAction.skipBack);
    });
  });

  group('counting presses', () {
    late List<int> reported;
    late MediaButtonPresses presses;

    setUp(() {
      reported = [];
      presses = MediaButtonPresses(reported.add);
    });

    testWidgets('one press plays or pauses once no second one comes',
        (tester) async {
      presses.press();
      await tester.pump(const Duration(milliseconds: 299));
      expect(reported, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reported, [1]);
    });

    testWidgets(
        'a second press soon after counts with the first, and waits '
        'for a third', (tester) async {
      presses.press();
      await tester.pump(const Duration(milliseconds: 250));
      presses.press();
      await tester.pump(const Duration(milliseconds: 250));
      expect(reported, isEmpty);
      await tester.pump(const Duration(milliseconds: 50));
      expect(reported, [2]);
    });

    testWidgets('the third goes at once; the next press starts over',
        (tester) async {
      presses
        ..press()
        ..press()
        ..press();
      expect(reported, [3]);

      presses.press();
      await tester.pump(MediaButtonPresses.defaultWindow);
      expect(reported, [3, 1]);
    });

    testWidgets('presses further apart count apart', (tester) async {
      presses.press();
      await tester.pump(const Duration(milliseconds: 400));
      presses.press();
      await tester.pump(const Duration(milliseconds: 400));
      expect(reported, [1, 1]);
    });

    testWidgets('stopped in between: the presses are forgotten',
        (tester) async {
      presses
        ..press()
        ..press()
        ..cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(reported, isEmpty);
    });
  });
}
