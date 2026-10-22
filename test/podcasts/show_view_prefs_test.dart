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

  test('search finds episodes by title or notes, any case', () {
    const episode = MediaItem(
        id: 'podcast_x',
        title: 'The Big Interview',
        extras: {'description': '<p>With <b>Ada Lovelace</b></p>'});
    expect(podcastEpisodeMatches(episode, 'big inter'), isTrue);
    expect(podcastEpisodeMatches(episode, 'lovelace'), isTrue);
    expect(podcastEpisodeMatches(episode, ' '), isTrue);
    expect(podcastEpisodeMatches(episode, 'babbage'), isFalse);
  });

  test('previews and search read a link as its words', () {
    expect(podcastPlainText('Our [sponsor](https://ex.com/s)\n\nBye'),
        'Our sponsor Bye');
    const episode = MediaItem(
        id: 'podcast_y',
        title: 'Ep',
        extras: {'description': 'Thanks to [Acme](https://acme.example)'});
    expect(podcastEpisodeMatches(episode, 'acme'), isTrue);
    expect(podcastEpisodeMatches(episode, 'example'), isFalse);
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

    test('a serial show lists oldest first until set otherwise', () async {
      expect(PodcastShowViewPrefs.oldestFirst('serial', serial: true), isTrue);
      await PodcastShowViewPrefs.setOldestFirst('serial', false);
      expect(PodcastShowViewPrefs.oldestFirst('serial', serial: true), isFalse);
      await PodcastShowViewPrefs.setOldestFirst('serial', true);
      expect(PodcastShowViewPrefs.oldestFirst('serial', serial: true), isTrue);
    });

    Future<List<int>> pumpShow(WidgetTester tester,
        {List<MediaItem>? episodes, String description = ''}) async {
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
          description: description,
          episodes: episodes ?? _episodes,
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

    testWidgets(
        'a serial show starts from its first episode, then plays on in '
        'order', (tester) async {
      MediaItem serial(int n) => MediaItem(
          id: 'podcast_ep$n',
          title: 'Episode $n',
          extras: const {'isPodcast': true, 'serial': true});
      final played =
          await pumpShow(tester, episodes: [serial(3), serial(2), serial(1)]);
      expect(top(tester, 'Episode 1'), lessThan(top(tester, 'Episode 3')));
      await tester.tap(find.text('firstEpisode'));
      expect(played, [2]);

      await _markPlayed(tester, ['podcast_ep1']);
      await tester.pump();
      await tester.tap(find.text('nextEpisode'));
      expect(played, [2, 1]);
    });

    testWidgets('newest first, the button plays the latest as before',
        (tester) async {
      final played = await pumpShow(tester);
      await tester.tap(find.text('latestEpisode'));
      expect(played, [0]);
    });

    testWidgets(
        'About opens to the show\'s own words, its links opening and its '
        'times staying text', (tester) async {
      await pumpShow(tester,
          description: 'Live every week at 12:34.\n\n'
              '[Support the show](https://patreon.example/show)');
      expect(find.text('Live every week at 12:34. Support the show'),
          findsOneWidget);

      await tester.tap(find.text('readMore'));
      await tester.pump();
      final spans = <TextSpan>[];
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan) spans.add(span);
          return true;
        });
      }
      final link = spans.firstWhere((s) => s.text == 'Support the show');
      expect(link.recognizer, isNotNull);
      expect(spans.any((s) => s.text == '12:34'), isFalse);
    });

    testWidgets('played episodes hidden, also when played later',
        (tester) async {
      await _markPlayed(tester, ['podcast_ep2']);
      final played = await pumpShow(tester);
      expect(find.text('Episode 2'), findsOneWidget);
      expect(find.text('showEpisodes · 3'), findsOneWidget);

      await tester.tap(find.byTooltip('hidePlayedEpisodes'));
      await tester.pump();
      expect(find.text('Episode 2'), findsNothing);
      expect(find.text('showEpisodes · 2'), findsOneWidget);
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
      expect(find.text('showEpisodes · 3'), findsOneWidget);
      expect(PodcastShowViewPrefs.hidePlayed('feed'), isFalse);
    });
    testWidgets('search the episodes, then close the search', (tester) async {
      await pumpShow(tester);
      await tester.tap(find.byTooltip('searchEpisodes'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'episode 2');
      await tester.pump();
      expect(find.text('Episode 2'), findsOneWidget);
      expect(find.text('Episode 1'), findsNothing);
      expect(find.text('showEpisodes · 1'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nothing like it');
      await tester.pump();
      expect(find.text('noEpisodesMatch'), findsOneWidget);

      await tester.tap(find.byTooltip('close'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('showEpisodes · 3'), findsOneWidget);
    });
  });
}
