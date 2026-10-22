import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_history.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_history_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

MediaItem _episode(int n) => MediaItem(
      id: 'podcast_ep$n',
      title: 'Episode $n',
      artist: 'Show',
      duration: const Duration(minutes: 30),
      extras: const {'isPodcast': true, 'url': 'https://example.com/ep.mp3'},
    );

const _boxes = [PodcastHistory.box, 'PodcastProgress', 'PodcastPlayed'];

List<String> _ids() => [for (final e in PodcastHistory.all) e.id];

void main() {
  final now = DateTime(2026, 10, 13, 21);

  test('days: Today, Yesterday, then the date', () {
    expect(podcastHistoryDay(DateTime(2026, 10, 13, 0, 5), now), 'today');
    expect(podcastHistoryDay(DateTime(2026, 10, 12, 23, 59), now), 'yesterday');
    expect(podcastHistoryDay(DateTime(2026, 10, 1, 12), now), '1 Oct 2026');
    expect(podcastHistoryDay(DateTime(2026, 9, 30), DateTime(2026, 10, 1, 8)),
        'yesterday');
  });

  group('kept', () {
    setUp(() async {
      for (final name in _boxes) {
        await Hive.openBox(name, bytes: Uint8List(0));
      }
    });
    tearDown(() async {
      for (final name in _boxes) {
        await Hive.box(name).close();
      }
    });

    test('newest first, once per episode, podcasts only', () async {
      await PodcastHistory.add(_episode(1), now: DateTime(2026, 10, 12, 9));
      await PodcastHistory.add(_episode(2), now: DateTime(2026, 10, 13, 8));
      await PodcastHistory.add(const MediaItem(id: 'song', title: 'Song'),
          now: now);
      expect(_ids(), ['podcast_ep2', 'podcast_ep1']);
      expect(
          [for (final d in podcastHistoryByDay(PodcastHistory.all, now)) d.$1],
          ['today', 'yesterday']);

      // Played again: back on top, still once.
      await PodcastHistory.add(_episode(1), now: now);
      expect(_ids(), ['podcast_ep1', 'podcast_ep2']);

      // Playable again from the history.
      final item = PodcastHistory.all.first.item!;
      expect(item.title, 'Episode 1');
      expect(item.extras?['url'], 'https://example.com/ep.mp3');
    });

    test('at most maxEntries: the oldest go', () async {
      final start = DateTime(2026, 1, 1);
      for (var i = 0; i <= PodcastHistory.maxEntries; i++) {
        await PodcastHistory.add(_episode(i),
            now: start.add(Duration(minutes: i)));
      }
      final ids = _ids();
      expect(ids, hasLength(PodcastHistory.maxEntries));
      expect(ids.first, 'podcast_ep${PodcastHistory.maxEntries}');
      expect(ids.last, 'podcast_ep1');
    });

    test('remove and clear, with Undo', () async {
      await PodcastHistory.add(_episode(1),
          now: now.subtract(const Duration(minutes: 40)));
      await PodcastHistory.add(_episode(2), now: now);
      final oldest = PodcastHistory.all.last;
      await PodcastHistory.remove(oldest.id);
      expect(_ids(), ['podcast_ep2']);
      await PodcastHistory.restore([oldest]);
      expect(_ids(), hasLength(2));

      final all = PodcastHistory.all;
      await PodcastHistory.clear();
      expect(PodcastHistory.all, isEmpty);
      await PodcastHistory.restore(all);
      expect(_ids(), [for (final e in all) e.id]);
    });

    Future<void> pumpHistory(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: PodcastHistoryScreen()),
      ));
    }

    Future<void> played(WidgetTester tester) => tester.runAsync(() async {
          final today = DateTime.now();
          await PodcastHistory.add(_episode(1),
              now: today.subtract(const Duration(days: 1)));
          await PodcastHistory.add(_episode(2), now: today);
        });

    testWidgets('nothing played yet', (tester) async {
      await pumpHistory(tester);
      expect(find.text('noListeningHistory'), findsOneWidget);
    });

    testWidgets('by day; swipe one away, then Undo', (tester) async {
      await played(tester);
      await pumpHistory(tester);
      expect(find.text('today'), findsOneWidget);
      expect(find.text('yesterday'), findsOneWidget);
      expect(find.text('Episode 2'), findsOneWidget);
      expect(find.text('Show · 30m'), findsNWidgets(2));

      await tester.drag(find.text('Episode 2'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Episode 2'), findsNothing);
      expect(find.text('today'), findsNothing);
      expect(_ids(), ['podcast_ep1']);
      expect(find.text('removedFromHistory'), findsOneWidget);

      await tester.tap(find.text('undo'));
      await tester.pumpAndSettle();
      expect(find.text('Episode 2'), findsOneWidget);
      expect(_ids(), ['podcast_ep2', 'podcast_ep1']);
    });

    testWidgets('Clear history, then Undo', (tester) async {
      await played(tester);
      await pumpHistory(tester);
      await tester.tap(find.text('clearHistory'));
      await tester.pumpAndSettle();
      expect(find.text('noListeningHistory'), findsOneWidget);
      expect(PodcastHistory.all, isEmpty);

      await tester.tap(find.text('undo'));
      await tester.pumpAndSettle();
      expect(find.text('Episode 1'), findsOneWidget);
      expect(find.text('Episode 2'), findsOneWidget);
    });
  });
}
