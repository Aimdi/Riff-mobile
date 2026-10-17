import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_library.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_library_ui.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _feedA = 'https://a.example/feed';
const _feedB = 'https://b.example/feed';

final _t0 = DateTime(2026, 10, 1, 12);

int _at(Duration d) => _t0.add(d).millisecondsSinceEpoch;

MediaItem _ep(String id, {String feed = _feedA, int? pub}) => MediaItem(
      id: id,
      title: id,
      extras: {
        'isPodcast': true,
        'feedUrl': feed,
        if (pub != null) 'pubDateMs': pub,
      },
    );

MediaItem _yt(String id) => MediaItem(
    id: id,
    title: id,
    extras: {'isPodcast': true, 'podcastPlaylistId': 'PLshow'});

void main() {
  group('which episodes are new', () {
    final since = _at(Duration.zero);
    final eps = [
      _ep('new2', pub: _at(const Duration(hours: 2))),
      _ep('new1', pub: _at(const Duration(hours: 1))),
      _ep('old', pub: _at(const Duration(days: -1))),
      _ep('undated'),
    ];

    test('first look: dated ones out since, oldest first; undated noted', () {
      expect(newEpisodesSince(eps, seen: null, sinceMs: since).map((e) => e.id),
          ['new1', 'new2']);
    });

    test('later: anything not seen before, still never older ones', () {
      expect(
          newEpisodesSince(eps, seen: {'new1'}, sinceMs: since)
              .map((e) => e.id),
          ['undated', 'new2']);
      expect(
          newEpisodesSince(eps,
              seen: {'new1', 'new2', 'undated'}, sinceMs: since),
          isEmpty);
    });

    test('junk stays off', () {
      expect(parseNewEpisodesQueue('top'), NewEpisodesQueue.top);
      expect(parseNewEpisodesQueue('sideways'), NewEpisodesQueue.off);
      expect(parseNewEpisodesQueue(null), NewEpisodesQueue.off);
    });
  });

  group('with the queue', () {
    late PodcastQueueController queue;

    setUp(() async {
      for (final b in [
        PodcastLibrary.showBox,
        PodcastLibrary.archiveBox,
        'PodcastPlayed',
        'PodcastProgress',
        'PodcastQueue',
      ]) {
        await Hive.openBox(b, bytes: Uint8List(0));
      }
      queue = Get.put(PodcastQueueController());
    });

    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    List<String> queued() => queue.queue.map((e) => e.id).toList();

    test('new episodes join at the end, once, unplayed and newer only',
        () async {
      await PodcastLibrary.setShowNewEpisodesQueue(_feedA, NewEpisodesQueue.end,
          now: _t0);
      final inbox = [
        _ep('a3', pub: _at(const Duration(hours: 2))),
        _ep('a2', pub: _at(const Duration(hours: 1))),
        _ep('a1', pub: _at(const Duration(days: -3))),
        _ep('b1', feed: _feedB, pub: _at(const Duration(hours: 3))),
      ];
      PodcastLibrary.queueNewEpisodes(inbox);
      expect(queued(), ['a2', 'a3']);

      // Taken out of the queue: not put back by the next refresh.
      queue.removeById('a2');
      PodcastLibrary.queueNewEpisodes(inbox);
      expect(queued(), ['a3']);

      // A new one, and one already played elsewhere.
      await Hive.box('PodcastPlayed').put('a5', 1);
      PodcastLibrary.queueNewEpisodes([
        _ep('a5', pub: _at(const Duration(days: 2))),
        _ep('a4', pub: _at(const Duration(days: 1))),
        ...inbox,
      ]);
      expect(queued(), ['a3', 'a4']);
    });

    test('at the top, a show of its own', () async {
      queue.add(_ep('x1', feed: _feedB));
      await PodcastLibrary.setShowNewEpisodesQueue(_feedA, NewEpisodesQueue.top,
          now: _t0);
      PodcastLibrary.queueNewEpisodes([
        _ep('a2', pub: _at(const Duration(hours: 2))),
        _ep('a1', pub: _at(const Duration(hours: 1))),
      ]);
      expect(queued(), ['a1', 'a2', 'x1']);
      // Switching to the end keeps what's been looked at.
      await PodcastLibrary.setShowNewEpisodesQueue(
          _feedA, NewEpisodesQueue.end);
      queue.clear();
      PodcastLibrary.queueNewEpisodes([
        _ep('a2', pub: _at(const Duration(hours: 2))),
        _ep('a1', pub: _at(const Duration(hours: 1))),
      ]);
      expect(queued(), isEmpty);
    });

    test('off adds nothing; on again counts from then', () async {
      await PodcastLibrary.setShowNewEpisodesQueue(_feedA, NewEpisodesQueue.end,
          now: _t0);
      await PodcastLibrary.setShowNewEpisodesQueue(
          _feedA, NewEpisodesQueue.off);
      expect(PodcastLibrary.newEpisodesQueueFor(_feedA), NewEpisodesQueue.off);
      expect(Hive.box(PodcastLibrary.showBox).get(_feedA), isNull);
      final inbox = [_ep('a1', pub: _at(const Duration(hours: 1)))];
      PodcastLibrary.queueNewEpisodes(inbox);
      expect(queued(), isEmpty);

      await PodcastLibrary.setShowNewEpisodesQueue(_feedA, NewEpisodesQueue.end,
          now: _t0.add(const Duration(days: 1)));
      PodcastLibrary.queueNewEpisodes(inbox);
      expect(queued(), isEmpty);
    });

    test('a YouTube show (no dates): the first look only notes', () async {
      await PodcastLibrary.setShowNewEpisodesQueue(
          'yt:PLshow', NewEpisodesQueue.end,
          now: _t0);
      PodcastLibrary.queueNewEpisodes([_yt('y2'), _yt('y1')]);
      expect(queued(), isEmpty);
      PodcastLibrary.queueNewEpisodes([_yt('y3'), _yt('y2'), _yt('y1')]);
      expect(queued(), ['y3']);
    });

    testWidgets('the show sheet sets it', (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PodcastLibraryEditor(showKey: _feedA),
          ),
        ),
      ));
      expect(find.text('newEpisodesToQueue'), findsOneWidget);
      await tester.ensureVisible(find.text('newEpisodesQueue_end'));
      await tester.tap(find.text('newEpisodesQueue_end'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(PodcastLibrary.newEpisodesQueueFor(_feedA), NewEpisodesQueue.end);
    });

    testWidgets('not in the defaults (Podcast settings)', (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(
          body: SingleChildScrollView(child: PodcastLibraryEditor()),
        ),
      ));
      expect(find.text('newEpisodesToQueue'), findsNothing);
    });
  });
}
