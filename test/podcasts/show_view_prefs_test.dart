import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_progress_service.dart';
import 'package:harmonymusic/services/podcast_show_view_prefs.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_show_view.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

MediaItem _episode(int n) => MediaItem(
      id: 'podcast_ep$n',
      title: 'Episode $n',
      artist: 'Show',
      duration: const Duration(minutes: 30),
      extras: const {'isPodcast': true},
    );

/// Feed order: newest first.
final _episodes = [_episode(3), _episode(2), _episode(1)];

const _boxes = ['AppPrefs', 'PodcastProgress', 'PodcastPlayed'];

/// Marks episodes played (real async) and lets the change reach the page.
Future<void> _markPlayed(WidgetTester tester, List<String> ids) =>
    tester.runAsync(() async {
      ids.forEach(PodcastProgressService.markPlayed);
      await Future<void>.delayed(Duration.zero);
    });

void main() {
  test('episodes newest or oldest first, without the hidden ones', () {
    expect(showEpisodeOrder(3, oldestFirst: false), [0, 1, 2]);
    expect(showEpisodeOrder(3, oldestFirst: true), [2, 1, 0]);
    expect(
        showEpisodeOrder(3, oldestFirst: true, hidden: (i) => i == 1), [2, 0]);
    expect(
        showEpisodeOrder(2, oldestFirst: false, hidden: (_) => true), isEmpty);
    expect(showEpisodeOrder(0, oldestFirst: true), isEmpty);
  });

  group('kept per show', () {
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

    test('each show has its own order and played filter', () async {
      expect(PodcastShowViewPrefs.oldestFirst('feed'), isFalse);
      expect(PodcastShowViewPrefs.hidePlayed('feed'), isFalse);

      await PodcastShowViewPrefs.setOldestFirst('feed', true);
      await PodcastShowViewPrefs.setHidePlayed('yt:list', true);
      expect(PodcastShowViewPrefs.oldestFirst('feed'), isTrue);
      expect(PodcastShowViewPrefs.hidePlayed('feed'), isFalse);
      expect(PodcastShowViewPrefs.oldestFirst('yt:list'), isFalse);
      expect(PodcastShowViewPrefs.hidePlayed('yt:list'), isTrue);
      expect(PodcastShowViewPrefs.oldestFirst(null), isFalse);

      await PodcastShowViewPrefs.setOldestFirst('feed', false);
      expect(PodcastShowViewPrefs.oldestFirst('feed'), isFalse);
      expect(Hive.box('AppPrefs').get(PodcastShowViewPrefs.oldestFirstKey),
          isEmpty);
    });

    Future<List<int>> pumpShow(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final played = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: PodcastShowView(
          title: 'Show',
          author: 'Host',
          artUrl: '',
          description: '',
          episodes: _episodes,
          loading: false,
          subscribed: true,
          onToggleSubscribe: () {},
          onPlay: played.add,
          playbackKey: 'feed',
        ),
      ));
      return played;
    }

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('oldest first stays when the show opens again', (tester) async {
      await pumpShow(tester);
      expect(top(tester, 'Episode 3'), lessThan(top(tester, 'Episode 1')));

      await tester.tap(find.text('newestFirst'));
      await tester.pump();
      expect(top(tester, 'Episode 1'), lessThan(top(tester, 'Episode 3')));
      expect(PodcastShowViewPrefs.oldestFirst('feed'), isTrue);

      await tester.pumpWidget(const SizedBox());
      final played = await pumpShow(tester);
      expect(find.text('oldestFirst'), findsOneWidget);
      expect(top(tester, 'Episode 1'), lessThan(top(tester, 'Episode 3')));

      // Still plays the episode tapped (feed order index).
      await tester.tap(find.text('Episode 1'));
      expect(played, [2]);
    });

    testWidgets('played episodes hidden, also when played later',
        (tester) async {
      await _markPlayed(tester, ['podcast_ep2']);
      final played = await pumpShow(tester);
      expect(find.text('Episode 2'), findsOneWidget);
      expect(find.text('SHOWEPISODES · 3'), findsOneWidget);

      await tester.tap(find.byTooltip('hidePlayedEpisodes'));
      await tester.pump();
      expect(find.text('Episode 2'), findsNothing);
      expect(find.text('SHOWEPISODES · 2'), findsOneWidget);
      expect(PodcastShowViewPrefs.hidePlayed('feed'), isTrue);

      await tester.tap(find.text('Episode 1'));
      expect(played, [2]);

      // Finished while the page is open: it goes too.
      await _markPlayed(tester, ['podcast_ep1']);
      await tester.pump();
      expect(find.text('Episode 1'), findsNothing);
      expect(find.text('Episode 3'), findsOneWidget);

      await _markPlayed(tester, ['podcast_ep3']);
      await tester.pump();
      expect(find.text('allEpisodesPlayed'), findsOneWidget);

      // Shown again from the same button.
      await tester.tap(find.byTooltip('showPlayedEpisodes'));
      await tester.pump();
      expect(find.text('Episode 2'), findsOneWidget);
      expect(find.text('SHOWEPISODES · 3'), findsOneWidget);
      expect(PodcastShowViewPrefs.hidePlayed('feed'), isFalse);
    });
  });
}
