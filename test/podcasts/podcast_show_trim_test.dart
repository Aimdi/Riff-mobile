import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:harmonymusic/services/podcast_progress_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_playback_controls.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

MediaItem _episode(String feed, {Duration? duration}) => MediaItem(
      id: 'podcast_$feed',
      title: 'Episode',
      artist: 'Show',
      duration: duration,
      extras: {
        'url': 'https://example.com/ep.mp3',
        'isPodcast': true,
        'feedUrl': feed,
      },
    );

void main() {
  group('PodcastShowTrim', () {
    test('lengths snap to the stepper choices', () {
      expect(PodcastShowTrim.snap(null), 0);
      expect(PodcastShowTrim.snap('30'), 0);
      expect(PodcastShowTrim.snap(double.nan), 0);
      expect(PodcastShowTrim.snap(-5), 0);
      expect(PodcastShowTrim.snap(7), 5);
      expect(PodcastShowTrim.snap(33), 35);
      expect(PodcastShowTrim.snap(62), 60);
      expect(PodcastShowTrim.snap(1000), PodcastShowTrim.maxSec);
    });

    test('steps go by 5 s to a minute, then 15 s, within range', () {
      expect(PodcastShowTrim.step(0, up: true), 5);
      expect(PodcastShowTrim.step(0, up: false), 0);
      expect(PodcastShowTrim.step(55, up: true), 60);
      expect(PodcastShowTrim.step(60, up: true), 75);
      expect(PodcastShowTrim.step(75, up: false), 60);
      expect(PodcastShowTrim.step(62, up: true), 75);
      expect(PodcastShowTrim.step(300, up: true), 300);
    });

    test('reads stored maps and tolerates junk', () {
      const trim = PodcastShowTrim(introSec: 30, outroSec: 90);
      expect(PodcastShowTrim.fromMap(trim.toMap()), trim);
      expect(PodcastShowTrim.fromMap('nonsense'), const PodcastShowTrim());
      expect(PodcastShowTrim.fromMap({'intro': 'x', 'outro': 33}),
          const PodcastShowTrim(outroSec: 35));
      expect(const PodcastShowTrim().isOn, isFalse);
      expect(const PodcastShowTrim(outroSec: 5).isOn, isTrue);
    });
  });

  group('where an episode starts and ends', () {
    const intro = PodcastShowTrim(introSec: 30);
    const outro = PodcastShowTrim(outroSec: 90);
    const halfHour = 30 * 60 * 1000;

    test('starts past the intro unless resuming beyond it', () {
      expect(podcastStartMs(savedMs: 0, trim: intro), 30000);
      expect(podcastStartMs(savedMs: 12000, trim: intro), 30000);
      expect(podcastStartMs(savedMs: 45000, trim: intro), 45000);
      expect(podcastStartMs(savedMs: 0, trim: const PodcastShowTrim()), 0);
      expect(podcastStartMs(savedMs: 0, trim: intro, totalMs: halfHour), 30000);
    });

    test('ends where the outro begins', () {
      expect(
          podcastOutroCutMs(totalMs: halfHour, trim: outro), halfHour - 90000);
      expect(podcastOutroCutMs(totalMs: halfHour, trim: intro), isNull);
      // Unknown length: nothing to cut from.
      expect(podcastOutroCutMs(totalMs: 0, trim: outro), isNull);
    });

    test('short episodes play whole', () {
      const both = PodcastShowTrim(introSec: 30, outroSec: 30);
      // 100 s less a 30 s intro and outro leaves under a minute.
      expect(podcastTrimFits(100000, both), isFalse);
      expect(podcastStartMs(savedMs: 0, trim: both, totalMs: 100000), 0);
      expect(podcastOutroCutMs(totalMs: 100000, trim: both), isNull);
      // Exactly a minute left is enough.
      expect(podcastTrimFits(120000, both), isTrue);
      expect(podcastOutroCutMs(totalMs: 120000, trim: both), 90000);
    });
  });

  group('stored per show (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_show_trim_');
      Hive.init(tmp.path);
      await Hive.openBox('AppPrefs');
      await Hive.openBox(PodcastPlaybackPrefs.showBox);
      await Hive.openBox('PodcastProgress');
      await Hive.openBox('PodcastPlayed');
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('saved for one show, apart from its playback overrides', () async {
      const trim = PodcastShowTrim(introSec: 30, outroSec: 45);
      await PodcastPlaybackPrefs.setShowTrim('feed', trim);
      expect(PodcastPlaybackPrefs.showTrim('feed'), trim);
      expect(PodcastPlaybackPrefs.trimForItem(_episode('feed')), trim);
      expect(PodcastPlaybackPrefs.showTrim('other').isOn, isFalse);
      expect(PodcastPlaybackPrefs.showTrim(null).isOn, isFalse);

      // Not an override: the show still follows the defaults, and
      // "Use global defaults" keeps the trim.
      expect(PodcastPlaybackPrefs.hasShowOverride('feed'), isFalse);
      await PodcastPlaybackPrefs.setShowOverride(
          'feed', const PodcastPlaybackProfile(speed: 1.5));
      await PodcastPlaybackPrefs.clearShowOverride('feed');
      expect(PodcastPlaybackPrefs.showTrim('feed'), trim);

      // Both off: the entry goes.
      await PodcastPlaybackPrefs.setShowTrim('feed', const PodcastShowTrim());
      expect(
          Hive.box(PodcastPlaybackPrefs.showBox)
              .containsKey(PodcastPlaybackPrefs.trimKey('feed')),
          isFalse);
    });

    test('an episode in the skipped outro counts as played', () async {
      const halfHour = Duration(minutes: 30);
      await PodcastPlaybackPrefs.setShowTrim(
          'feed', const PodcastShowTrim(outroSec: 90));
      // 28:35 is past the 28:30 cut, but neither in the last 20 s nor
      // at 98 %.
      const pos = Duration(minutes: 28, seconds: 35);

      final trimmed = _episode('feed', duration: halfHour);
      PodcastProgressService.save(trimmed, pos, halfHour, nowMs: 1);
      expect(PodcastProgressService.isPlayed(trimmed.id), isTrue);
      expect(PodcastProgressService.positionMs(trimmed.id), isNull);

      final plain = _episode('other', duration: halfHour);
      PodcastProgressService.save(plain, pos, halfHour, nowMs: 1);
      expect(PodcastProgressService.isPlayed(plain.id), isFalse);
      expect(PodcastProgressService.positionMs(plain.id), pos.inMilliseconds);
    });
  });

  testWidgets('steppers move through the choices, also for screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var trim = const PodcastShowTrim();
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PodcastShowTrimEditor(
            trim: trim,
            onChanged: (t) => setState(() => trim = t),
          ),
        ),
      ),
    ));

    final less = find.widgetWithIcon(IconButton, Icons.remove_rounded);
    final more = find.widgetWithIcon(IconButton, Icons.add_rounded);
    expect(find.text('off'), findsNWidgets(2));
    expect(tester.widget<IconButton>(less.first).onPressed, isNull);

    await tester.tap(more.first);
    await tester.pump();
    expect(trim, const PodcastShowTrim(introSec: 5));
    expect(find.text('5 s'), findsOneWidget);

    tester.semantics.performAction(
        find.semantics.byLabel('skipOutro'), SemanticsAction.increase);
    await tester.pump();
    expect(trim, const PodcastShowTrim(introSec: 5, outroSec: 5));

    tester.semantics.performAction(
        find.semantics.byLabel('skipIntro'), SemanticsAction.decrease);
    await tester.pump();
    expect(trim, const PodcastShowTrim(outroSec: 5));
    semantics.dispose();
  });
}
