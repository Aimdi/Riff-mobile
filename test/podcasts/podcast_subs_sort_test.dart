import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/podcast_inbox_counts.dart';
import 'package:harmonymusic/services/podcast_subs_sort.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_cover_tile.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_subs_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

typedef _Show = ({String title, int latestMs, int followedMs});

List<String> _titles(List<_Show> shows, PodcastSubsSort sort) =>
    sortPodcastSubs<_Show>(shows, sort, (s) => s).map((s) => s.title).toList();

MediaItem _ep(String id, String feed, int pubMs) => MediaItem(
    id: id,
    title: id,
    extras: {'isPodcast': true, 'feedUrl': feed, 'pubDateMs': pubMs});

void main() {
  const shows = <_Show>[
    (title: 'beta', latestMs: 0, followedMs: 300),
    (title: 'Alpha', latestMs: 500, followedMs: 0),
    (title: 'gamma', latestMs: 900, followedMs: 100),
    (title: 'Delta', latestMs: 500, followedMs: 0),
  ];

  test('by name, any case; the default leaves them be', () {
    expect(_titles(shows, PodcastSubsSort.name),
        ['Alpha', 'beta', 'Delta', 'gamma']);
    expect(_titles(shows, PodcastSubsSort.standard),
        ['beta', 'Alpha', 'gamma', 'Delta']);
  });

  test('newest first, the unknown last, ties by name', () {
    expect(_titles(shows, PodcastSubsSort.latestEpisode),
        ['gamma', 'Alpha', 'Delta', 'beta']);
    expect(_titles(shows, PodcastSubsSort.recentlyFollowed),
        ['beta', 'gamma', 'Alpha', 'Delta']);
  });

  group('with the stores', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      await Hive.openBox('LibraryPodcasts', bytes: Uint8List(0));
      await Hive.openBox('PodcastPlayed', bytes: Uint8List(0));
    });
    tearDown(() async {
      await PodcastSubsOrder.set(PodcastSubsSort.standard);
      Get.reset();
      await Hive.close();
    });

    test('the choice is kept', () async {
      await PodcastSubsOrder.set(PodcastSubsSort.latestEpisode);
      expect(PodcastSubsOrder.sort.value, PodcastSubsSort.latestEpisode);
      expect(
          Hive.box('AppPrefs').get(PodcastSubsOrder.prefKey), 'latestEpisode');
    });

    test("each show's latest episode, from the Inbox", () {
      PodcastInboxCounts.setInbox([
        _ep('a1', 'https://a/feed', 100),
        _ep('a2', 'https://a/feed', 300),
        _ep('b1', 'https://b/feed', 200),
        _ep('undated', 'https://b/feed', 0),
      ]);
      expect(PodcastInboxCounts.latestByShow(),
          {'https://a/feed': 300, 'https://b/feed': 200});
    });

    test('library shows and feeds sorted together', () async {
      await Hive.box('LibraryPodcasts')
          .put('PLlib', {'title': 'Library Show', 'addedAt': 300});
      final library = [
        Playlist(
            title: 'Library Show',
            playlistId: 'PLlib',
            thumbnailUrl: Playlist.thumbPlaceholderUrl),
      ];
      final feeds = [
        {'title': 'Old Feed', 'feedUrl': 'https://a/feed', 'subscribedAt': 200},
        {'title': 'New Feed', 'feedUrl': 'https://b/feed', 'subscribedAt': 400},
      ];
      String titleOf(SubsShow s) => s.library?.title ?? '${s.feed!['title']}';

      await PodcastSubsOrder.set(PodcastSubsSort.recentlyFollowed);
      expect(sortedSubsShows(library, feeds).map(titleOf),
          ['New Feed', 'Library Show', 'Old Feed']);

      PodcastInboxCounts.setInbox([
        _ep('a1', 'https://a/feed', 900),
        _ep('b1', 'https://b/feed', 100),
        const MediaItem(
            id: 'y1',
            title: 'y1',
            extras: {'isPodcast': true, 'podcastPlaylistId': 'PLlib'}),
      ]);
      await PodcastSubsOrder.set(PodcastSubsSort.latestEpisode);
      expect(sortedSubsShows(library, feeds).map(titleOf),
          ['Old Feed', 'New Feed', 'Library Show']);

      await PodcastSubsOrder.set(PodcastSubsSort.standard);
      expect(sortedSubsShows(library, feeds).map(titleOf),
          ['Library Show', 'Old Feed', 'New Feed']);
    });

    testWidgets('the header menu picks it', (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: Center(child: PodcastSubsSortButton())),
      ));
      await tester.tap(find.byType(PodcastSubsSortButton));
      await tester.pumpAndSettle();
      expect(find.text('sortDefault'), findsOneWidget);
      await tester.tap(find.text('sortName'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(PodcastSubsOrder.sort.value, PodcastSubsSort.name);
      final icon = tester.widget<Icon>(find.byIcon(Icons.sort_rounded));
      expect(icon.color,
          RiffTheme.dark(const Color(0xFF1DB954)).colorScheme.primary);
    });
  });
}
