import 'package:audio_service/audio_service.dart' show MediaButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/headphone_controls.dart';
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

  group("headphones' and car stereos' own next and previous", () {
    test('music: the next or previous song', () {
      expect(mediaButtonPressed(MediaButton.next, longForm: false),
          MediaButtonAction.next);
      expect(mediaButtonPressed(MediaButton.previous, longForm: false),
          MediaButtonAction.previous);
      expect(mediaButtonPressed(MediaButton.media, longForm: false),
          MediaButtonAction.playPause);
    });

    test('episodes and books skip forward and back, not on or from the start',
        () {
      expect(mediaButtonPressed(MediaButton.next, longForm: true),
          MediaButtonAction.skipForward);
      expect(mediaButtonPressed(MediaButton.previous, longForm: true),
          MediaButtonAction.skipBack);
      expect(mediaButtonPressed(MediaButton.media, longForm: true),
          MediaButtonAction.playPause);
    });
  });

  group("an episode's headphone buttons, as set", () {
    MediaButtonAction pressed(MediaButton button, HeadphoneAction action,
            {bool podcast = true, bool longForm = true}) =>
        mediaButtonPressed(button,
            longForm: longForm,
            podcast: podcast,
            nextAction: action,
            previousAction: action);

    test('chapters, a bookmark, or the next or previous episode', () {
      expect(pressed(MediaButton.next, HeadphoneAction.chapter),
          MediaButtonAction.nextChapter);
      expect(pressed(MediaButton.previous, HeadphoneAction.chapter),
          MediaButtonAction.previousChapter);
      expect(pressed(MediaButton.next, HeadphoneAction.bookmark),
          MediaButtonAction.bookmark);
      expect(pressed(MediaButton.previous, HeadphoneAction.episode),
          MediaButtonAction.previous);
      expect(pressed(MediaButton.next, HeadphoneAction.skip),
          MediaButtonAction.skipForward);
    });

    test('next and previous each their own', () {
      expect(
          mediaButtonPressed(MediaButton.previous,
              longForm: true,
              podcast: true,
              nextAction: HeadphoneAction.bookmark,
              previousAction: HeadphoneAction.skip),
          MediaButtonAction.skipBack);
    });

    test("a one-button headset's presses do the same", () {
      expect(
          mediaButtonAction(2,
              longForm: true,
              podcast: true,
              nextAction: HeadphoneAction.chapter,
              previousAction: HeadphoneAction.bookmark),
          MediaButtonAction.nextChapter);
      expect(
          mediaButtonAction(3,
              longForm: true,
              podcast: true,
              nextAction: HeadphoneAction.chapter,
              previousAction: HeadphoneAction.bookmark),
          MediaButtonAction.bookmark);
      expect(
          mediaButtonAction(1,
              longForm: true,
              podcast: true,
              nextAction: HeadphoneAction.chapter),
          MediaButtonAction.playPause);
    });

    test('books and music keep theirs', () {
      expect(pressed(MediaButton.next, HeadphoneAction.chapter, podcast: false),
          MediaButtonAction.skipForward);
      expect(
          pressed(MediaButton.next, HeadphoneAction.chapter,
              podcast: false, longForm: false),
          MediaButtonAction.next);
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
