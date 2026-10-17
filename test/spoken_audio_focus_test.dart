import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:harmonymusic/services/spoken_audio_focus.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_settings_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/cust_switch.dart';
import 'package:hive/hive.dart';

const _song = MediaItem(id: 'song0000001', title: 'Song');
const _episode =
    MediaItem(id: 'podcast_ep1', title: 'Episode', extras: {'isPodcast': true});
const _book = MediaItem(id: 'abs_book1_0', title: 'Chapter 1');

/// Spoken word pauses for a navigation prompt or a notification sound
/// (Android's "will pause when ducked"); music plays on quieter.
void main() {
  late List<String> calls;
  late bool playing;
  late bool pauses;

  SpokenAudioFocus focus({bool failing = false}) => SpokenAudioFocus(
        configure: (configuration) async {
          if (failing) throw UnsupportedError('no audio session');
          calls.add(configuration.androidWillPauseWhenDucked == true
              ? 'speech'
              : 'music');
        },
        setActive: (active) async {
          calls.add(active ? 'ask' : 'give back');
          return true;
        },
        playing: () => playing,
        pauseForInterruptions: () => pauses,
      );

  setUp(() {
    calls = [];
    playing = true;
    pauses = true;
  });

  test('speech pauses when another app plays over it; music plays on', () {
    final speech = SpokenAudioFocus.configurationFor(pauses: true);
    expect(speech.androidWillPauseWhenDucked, isTrue);
    expect(speech.androidAudioAttributes?.contentType,
        AndroidAudioContentType.speech);
    final music = SpokenAudioFocus.configurationFor(pauses: false);
    expect(music.androidWillPauseWhenDucked, isNot(true));
    expect(music.androidAudioAttributes?.contentType,
        AndroidAudioContentType.music);
  });

  test('music, as the session started: left as it is', () async {
    final f = focus();
    await f.follow(_song);
    await f.follow(const MediaItem(id: 'song0000002', title: 'Next'));
    expect(calls, isEmpty);
  });

  test('an episode after music, playing: speech, and focus asked for again',
      () async {
    final f = focus();
    await f.follow(_song);
    await f.follow(_episode);
    expect(calls, ['speech', 'give back', 'ask']);

    // The next episode, a book: speech already.
    calls.clear();
    await f.follow(const MediaItem(
        id: 'podcast_ep2', title: 'Next', extras: {'isPodcast': true}));
    await f.follow(_book);
    expect(calls, isEmpty);
  });

  test('turned while paused: focus given back, the next play asks', () async {
    playing = false;
    final f = focus();
    await f.follow(_book);
    expect(calls, ['speech', 'give back']);

    calls.clear();
    await f.follow(_song);
    expect(calls, ['music', 'give back']);
  });

  test('nothing playing leaves it as it is', () async {
    final f = focus();
    await f.follow(_episode);
    calls.clear();
    await f.follow(null);
    expect(calls, isEmpty);
  });

  test('Pause for interruptions off: an episode plays on quieter, as music',
      () async {
    pauses = false;
    final f = focus();
    await f.follow(_episode);
    expect(calls, isEmpty);

    // Turned on while it plays: speech from then on, and off again.
    pauses = true;
    await f.follow(_episode);
    expect(calls, ['speech', 'give back', 'ask']);
    calls.clear();
    pauses = false;
    await f.follow(_episode);
    expect(calls, ['music', 'give back', 'ask']);
  });

  test('one change at a time, in the order they came', () async {
    final f = focus();
    f.follow(_song);
    f.follow(_episode);
    f.follow(_song);
    await f.follow(_episode);
    expect(calls, [
      'speech', 'give back', 'ask', //
      'music', 'give back', 'ask', //
      'speech', 'give back', 'ask',
    ]);
  });

  test('where there is no audio session, it plays on as it was', () async {
    final f = focus(failing: true);
    await expectLater(f.follow(_episode), completes);
    expect(calls, isEmpty);
  });

  group('Podcast settings', () {
    setUp(() async {
      Hive.init('.');
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await Hive.close();
      Get.reset();
    });

    test('on unless turned off', () async {
      expect(PodcastPlaybackPrefs.pauseForInterruptions, isTrue);
      await PodcastPlaybackPrefs.setPauseForInterruptions(false);
      expect(PodcastPlaybackPrefs.pauseForInterruptions, isFalse);
      expect(Hive.box('AppPrefs').get('podcastPauseForInterruptions'), false);
    });

    testWidgets('a switch under Smart resume', (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const PodcastSettingsScreen(),
      ));
      final title = find.text('pauseForInterruptions');
      await tester.scrollUntilVisible(title, 200,
          scrollable: find.byType(Scrollable).first);
      // Under Smart resume.
      expect(tester.getTopLeft(title).dy,
          greaterThan(tester.getTopLeft(find.text('smartResume')).dy));
      expect(find.text('pauseForInterruptionsDes'), findsOneWidget);
      final toggle = find.descendant(
          of: find.ancestor(of: title, matching: find.byType(Row)).first,
          matching: find.byType(CustSwitch));
      expect(tester.widget<CustSwitch>(toggle).value, isTrue);

      await tester.runAsync(() async {
        tester.widget<CustSwitch>(toggle).onChanged!(false);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(PodcastPlaybackPrefs.pauseForInterruptions, isFalse);
      expect(tester.widget<CustSwitch>(toggle).value, isFalse);
    });
  });
}
