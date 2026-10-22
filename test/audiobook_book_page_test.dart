import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/audiobook_progress_service.dart';
import 'package:harmonymusic/services/audiobookshelf_service.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_book_page.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_play.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_layout.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/now_playing_bars.dart';
import 'package:hive/hive.dart';

Widget _app(Widget child) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: ListView(children: [child])),
    );

AbsBookDetail _book({double currentTime = 0}) => AbsBookDetail(
      id: 'b1',
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      currentTime: currentTime,
      tracks: [
        for (var n = 0; n < 4; n++)
          AbsAudioTrack(
            index: n,
            title: 'Chapter ${n + 1}',
            contentUrl: '/api/items/b1/file/$n',
            duration: 600,
          ),
      ],
    );

void main() {
  group('AudiobookChapterRow', () {
    testWidgets('number, title and length; a tap plays it', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(AudiobookChapterRow(
        number: 3,
        title: 'The Assembly at Meryton',
        durationSec: 25 * 60,
        onTap: () => taps++,
      )));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('The Assembly at Meryton'), findsOneWidget);
      expect(find.text('25m'), findsOneWidget);
      expect(find.byType(PodcastProgressBar), findsNothing);

      await tester.tap(find.text('The Assembly at Meryton'));
      expect(taps, 1);
    });

    testWidgets('playing: bars in place of the number, the title in accent',
        (tester) async {
      await tester.pumpWidget(_app(AudiobookChapterRow(
        number: 3,
        title: 'Chapter 3',
        durationSec: 60,
        playing: true,
        onTap: () {},
      )));
      expect(find.text('3'), findsNothing);
      expect(find.byType(NowPlayingBars), findsOneWidget);
      final context = tester.element(find.text('Chapter 3'));
      expect(tester.widget<Text>(find.text('Chapter 3')).style?.color,
          Theme.of(context).colorScheme.secondary);
    });

    testWidgets('a bar under the title only while partly heard',
        (tester) async {
      Future<void> pump(double p) => tester.pumpWidget(_app(AudiobookChapterRow(
          number: 1,
          title: 'Chapter 1',
          durationSec: 60,
          progress: p,
          onTap: () {})));
      await pump(0.4);
      expect(find.byType(PodcastProgressBar), findsOneWidget);
      await pump(0.99);
      expect(find.byType(PodcastProgressBar), findsNothing);
    });
  });

  testWidgets('AudiobookAbout: More unfolds the rest, Show less folds it',
      (tester) async {
    await tester.pumpWidget(_app(AudiobookAbout(
      description: List.filled(40, 'A long description.').join(' '),
      subjects: const ['fiction'],
    )));
    Text description() => tester.widget<Text>(find.textContaining('A long'));
    expect(description().maxLines, 4);
    expect(find.text('Fiction'), findsOneWidget);

    await tester.tap(find.text('readMore'.tr));
    await tester.pumpAndSettle();
    expect(description().maxLines, isNull);
    expect(find.text('showLess'.tr), findsOneWidget);
  });

  testWidgets('AudiobookAbout: no More when the description fits',
      (tester) async {
    await tester.pumpWidget(
        _app(const AudiobookAbout(description: 'A short description.')));
    expect(find.text('A short description.'), findsOneWidget);
    expect(find.text('readMore'.tr), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('AudiobookBookHeader: the Play pill stops growing on a tablet',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 2560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(AudiobookBookHeader(
        cover: '', title: 'T', author: '', playLabel: 'Play', onPlay: () {})));
    expect(
        tester.getSize(find.byWidgetPredicate((w) => w is FilledButton)).width,
        RiffComponentSizes.bookPlayMax);
  });

  testWidgets('AudiobookBookHeader: title, author, lines, and the Play pill',
      (tester) async {
    var plays = 0;
    await tester.pumpWidget(_app(AudiobookBookHeader(
      cover: '',
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      lines: const ['Narrator: Ray Porter', '', '14 chapters · 16h 10m'],
      playLabel: 'Resume · Chapter 7 of 14',
      onPlay: () => plays++,
    )));
    expect(find.text('Project Hail Mary'), findsOneWidget);
    expect(find.text('Andy Weir'), findsOneWidget);
    expect(find.text('Narrator: Ray Porter'), findsOneWidget);
    expect(find.text('14 chapters · 16h 10m'), findsOneWidget);
    await tester.tap(find.text('Resume · Chapter 7 of 14'));
    expect(plays, 1);
  });

  group('absResumePoint', () {
    setUp(() async {
      await Hive.openBox(AudiobookProgressService.boxName, bytes: Uint8List(0));
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    test("the server's place when this phone has none", () {
      // 25 minutes in: the third chapter, 5 minutes into it.
      expect(absResumePoint(_book(currentTime: 1500)), (2, 300000));
      expect(absResumePoint(_book()), (0, 0));
    });

    test("this phone's last place wins over the server's", () async {
      await Hive.box(AudiobookProgressService.boxName).put('abs_b1_1', {
        'id': AudiobookshelfService.trackMediaId('b1', 1),
        'bookId': 'b1',
        'positionMs': 42000,
        'updatedAt': 1,
      });
      expect(absResumePoint(_book(currentTime: 1500)), (1, 42000));
    });
  });
}
