import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_inbox_counts.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_cover_tile.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_folder_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _feedA = 'https://a.example/feed';
const _feedB = 'https://b.example/feed';

MediaItem _rss(String id, String feed) =>
    MediaItem(id: id, title: id, extras: {'isPodcast': true, 'feedUrl': feed});

MediaItem _yt(String id, String playlistId) => MediaItem(
    id: id,
    title: id,
    extras: {'isPodcast': true, 'podcastPlaylistId': playlistId});

/// The badge's spoken count (`.tr` gives the key in tests).
Finder _labelled(String label) => find
    .byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  test('a show counts its episodes neither played nor archived, once each', () {
    final inbox = [
      _rss('a1', _feedA),
      _rss('a2', _feedA),
      _rss('a3', _feedA),
      _rss('b1', _feedB),
      _yt('y1', 'MPSPPLshow'),
      _rss('a1', _feedA),
    ];
    expect(podcastWaitingCount(inbox, {_feedA}, done: (id) => id == 'a2'), 2);
    expect(podcastWaitingCount(inbox, {_feedB}, done: (_) => false), 1);
    // A YouTube show, whatever prefix its playlist id came with.
    expect(
        podcastWaitingCount(inbox, {podcastShowKeyForYoutube('VLPLshow')!},
            done: (_) => false),
        1);
    expect(podcastWaitingCount(inbox, const {}, done: (_) => false), 0);
  });

  test('a folder counts all its shows', () {
    final shows = podcastFolderShowKeys(['rss:$_feedA', 'PLshow', 'rss:']);
    expect(shows, {_feedA, 'yt:PLshow'});
    expect(
        podcastWaitingCount([
          _rss('a1', _feedA),
          _yt('y1', 'PLshow'),
          _rss('b1', _feedB)
        ], shows, done: (_) => false),
        2);
  });

  group('with the Inbox', () {
    setUp(() async {
      await Hive.openBox('PodcastPlayed', bytes: Uint8List(0));
      await Hive.openBox('PodcastArchived', bytes: Uint8List(0));
    });
    tearDown(() async {
      await Hive.box('PodcastPlayed').close();
      await Hive.box('PodcastArchived').close();
    });

    test('played and archived episodes leave the count', () async {
      PodcastInboxCounts.setInbox(
          [_rss('a1', _feedA), _rss('a2', _feedA), _rss('a3', _feedA)]);
      expect(PodcastInboxCounts.count({_feedA}), 3);
      await Hive.box('PodcastPlayed').put('a1', 1);
      await Hive.box('PodcastArchived').put('a2', {'at': 1, 'show': _feedA});
      expect(PodcastInboxCounts.count({_feedA}), 1);
      expect(PodcastInboxCounts.count({_feedB}), 0);
    });

    testWidgets('the cover shows the count and follows plays and refreshes',
        (tester) async {
      PodcastInboxCounts.setInbox([_rss('a1', _feedA), _rss('a2', _feedA)]);
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(
          body: SizedBox(
            width: 160,
            height: 240,
            child: PodcastCoverTile(
              title: 'Show A',
              cover: const SizedBox.expand(),
              count: podcastShowCountBadge(_feedA),
            ),
          ),
        ),
      ));
      expect(find.text('2'), findsOneWidget);
      expect(_labelled('newInInbox'), findsOneWidget);

      // Played elsewhere (the player, the Inbox): one left.
      await tester.runAsync(() => Hive.box('PodcastPlayed').put('a1', 1));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(_labelled('newInInboxOne'), findsOneWidget);

      // None left: no badge.
      await tester.runAsync(() => Hive.box('PodcastPlayed').put('a2', 1));
      await tester.pump();
      expect(find.text('1'), findsNothing);
      expect(find.byType(PodcastInboxCountBadge), findsOneWidget);

      // The Inbox refreshes with a new episode.
      PodcastInboxCounts.setInbox(
          [_rss('a3', _feedA), _rss('a1', _feedA), _rss('a2', _feedA)]);
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });
  });
}
