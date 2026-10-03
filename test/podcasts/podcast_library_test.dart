import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/opml.dart';
import 'package:harmonymusic/services/podcast_library.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_folder_controller.dart';
import 'package:hive/hive.dart';

MediaItem ep(String id, {String feed = 'https://a/feed', int pub = 0}) =>
    MediaItem(id: id, title: id, extras: {
      'isPodcast': true,
      'feedUrl': feed,
      'pubDateMs': pub,
    });

void main() {
  group('keep latest', () {
    bool none(String _) => false;

    test('keeps the newest N unplayed, archives the rest', () {
      expect(
          episodesToArchive(['e5', 'e4', 'e3', 'e2', 'e1'], 2,
              isPlayed: none, inProgress: none),
          ['e3', 'e2', 'e1']);
    });

    test('All (0) archives nothing', () {
      expect(episodesToArchive(['a', 'b'], 0, isPlayed: none, inProgress: none),
          isEmpty);
    });

    test('played ones do not count; started ones are never archived', () {
      expect(
          episodesToArchive(['e5', 'e4', 'e3', 'e2', 'e1'], 1,
              isPlayed: (id) => id == 'e5',
              inProgress: (id) => id == 'e2'),
          ['e3', 'e1']);
    });

    test('sortNewestFirst: by date, undated last in their order', () {
      final out = PodcastLibrary.sortNewestFirst(
          [ep('u1'), ep('old', pub: 1), ep('u2'), ep('new', pub: 9)]);
      expect(out.map((e) => e.id), ['new', 'old', 'u1', 'u2']);
    });
  });

  group('auto-delete', () {
    const day = 24 * 3600 * 1000;
    test('rules', () {
      expect(parseAutoDelete('after24h'), AutoDeletePolicy.after24h);
      expect(parseAutoDelete('junk'), AutoDeletePolicy.never);
      expect(parseAutoDelete(null), AutoDeletePolicy.never);
      expect(downloadDueForDeletion(AutoDeletePolicy.never, 0, day * 9), isFalse);
      expect(downloadDueForDeletion(AutoDeletePolicy.immediately, 5, 6), isTrue);
      expect(
          downloadDueForDeletion(AutoDeletePolicy.immediately, 5, 6,
              isCurrent: true),
          isFalse);
      expect(downloadDueForDeletion(AutoDeletePolicy.immediately, null, 6),
          isFalse);
      expect(downloadDueForDeletion(AutoDeletePolicy.after24h, 0, day - 1),
          isFalse);
      expect(downloadDueForDeletion(AutoDeletePolicy.after24h, 0, day), isTrue);
    });
  });

  group('filters', () {
    test('each chip', () {
      const fresh = EpisodeFacts();
      const started = EpisodeFacts(inProgress: true);
      const done = EpisodeFacts(played: true, downloaded: true);
      expect(matchesEpisodeFilter(null, done), isTrue);
      expect(matchesEpisodeFilter(EpisodeFilter.fresh, fresh), isTrue);
      expect(matchesEpisodeFilter(EpisodeFilter.fresh, started), isFalse);
      expect(matchesEpisodeFilter(EpisodeFilter.fresh, done), isFalse);
      expect(matchesEpisodeFilter(EpisodeFilter.inProgress, started), isTrue);
      expect(matchesEpisodeFilter(EpisodeFilter.downloaded, done), isTrue);
      expect(
          matchesEpisodeFilter(
              EpisodeFilter.queued, const EpisodeFacts(queued: true)),
          isTrue);
      expect(
          matchesEpisodeFilter(
              EpisodeFilter.bookmarked, const EpisodeFacts(bookmarked: true)),
          isTrue);
    });

    test('short is under 20 minutes, unknown length is not short', () {
      bool short(Duration? d) => matchesEpisodeFilter(
          EpisodeFilter.short, EpisodeFacts(duration: d));
      expect(short(const Duration(minutes: 19, seconds: 59)), isTrue);
      expect(short(const Duration(minutes: 20)), isFalse);
      expect(short(null), isFalse);
      expect(short(Duration.zero), isFalse);
    });

    test('uniqueEpisodes keeps the first copy, in order', () {
      final out = uniqueEpisodes([
        [ep('a'), ep('b')],
        [ep('b'), ep('c')],
      ]);
      expect(out.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('mark all plans only the unplayed', () {
      expect(planMarkAllListened(['a', 'b', 'c'], (id) => id == 'b'),
          ['a', 'c']);
    });
  });

  group('folders', () {
    test('feed shows get an rss: id; YouTube ids are left alone', () {
      expect(podcastFolderIdForFeed('https://a/feed'), 'rss:https://a/feed');
      expect(feedUrlFromFolderId('rss:https://a/feed'), 'https://a/feed');
      expect(feedUrlFromFolderId('PLabc'), isNull);
      // A folder saved by an older version still loads.
      final f = PodcastFolder.fromMap({'id': '1', 'name': 'Old', 'ids': ['PLx']});
      expect(f.podcastIds, ['PLx']);
    });

    test('reorder like ReorderableListView', () {
      expect(reorderList(['a', 'b', 'c'], 0, 3), ['b', 'c', 'a']);
      expect(reorderList(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
      expect(reorderList(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c']);
      expect(reorderList(['a'], 5, 0), ['a']);
    });
  });

  group('OPML', () {
    test('parse: nested folders, any case, junk and duplicates dropped', () {
      const src = '''<?xml version="1.0"?>
<opml version="1.1"><head><title>x</title></head><body>
  <outline text="Folder">
    <outline type="rss" text="Show A" xmlUrl="https://a.example/feed"/>
    <outline type="rss" title="Show B" xmlurl="http://b.example/rss"/>
  </outline>
  <outline type="rss" text="Dup" xmlUrl="https://a.example/feed"/>
  <outline type="rss" text="Bad" xmlUrl="ftp://nope"/>
  <outline text="No url"/>
</body></opml>''';
      final out = parseOpml(src);
      expect(out.map((f) => f.feedUrl),
          ['https://a.example/feed', 'http://b.example/rss']);
      expect(out.map((f) => f.title), ['Show A', 'Show B']);
    });

    test('garbage is empty', () {
      expect(parseOpml('not xml at all <'), isEmpty);
      expect(parseOpml(''), isEmpty);
    });

    test('build round trips, escapes and dates in RFC 822', () {
      final xml = buildOpml(const [
        OpmlFeed(feedUrl: 'https://a.example/feed?x=1&y=2', title: 'A & B'),
        OpmlFeed(feedUrl: 'https://c.example/rss', title: 'C'),
      ], now: DateTime.utc(2026, 10, 3, 9, 5, 7));
      expect(xml, contains('Sat, 03 Oct 2026 09:05:07 GMT'));
      expect(xml, contains('A &amp; B'));
      final back = parseOpml(xml);
      expect(back.map((f) => f.feedUrl),
          ['https://a.example/feed?x=1&y=2', 'https://c.example/rss']);
      expect(back.first.title, 'A & B');
    });
  });

  group('store (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_library_');
      Hive.init(tmp.path);
      for (final b in [
        'AppPrefs',
        PodcastLibrary.showBox,
        PodcastLibrary.archiveBox,
        'PodcastProgress',
        'PodcastPlayed',
      ]) {
        await Hive.openBox(b);
      }
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('defaults, per-show overrides, junk values', () async {
      expect(PodcastLibrary.keepLatestFor('s'), 0);
      expect(PodcastLibrary.autoDeleteFor('s'), AutoDeletePolicy.never);
      await PodcastLibrary.setDefaultKeepLatest(5);
      await PodcastLibrary.setShowKeepLatest('s', 1);
      expect(PodcastLibrary.keepLatestFor('s'), 1);
      expect(PodcastLibrary.keepLatestFor('other'), 5);
      await PodcastLibrary.setShowKeepLatest('s', null);
      expect(PodcastLibrary.keepOverride('s'), isNull);
      await Hive.box('AppPrefs').put(PodcastLibrary.keepKey, 7);
      expect(PodcastLibrary.defaultKeepLatest, 0);
      await PodcastLibrary.setShowAutoDelete('s', AutoDeletePolicy.after24h);
      expect(PodcastLibrary.autoDeleteFor('s'), AutoDeletePolicy.after24h);
    });

    test('applyKeepLatest archives per show; a new limit unarchives', () async {
      const feedA = 'https://a/feed';
      const feedB = 'https://b/feed';
      await PodcastLibrary.setShowKeepLatest(feedA, 1);
      final merged = [
        ep('a3', feed: feedA, pub: 30),
        ep('b2', feed: feedB, pub: 25),
        ep('a2', feed: feedA, pub: 20),
        ep('a1', feed: feedA, pub: 10),
        ep('b1', feed: feedB, pub: 5),
      ];
      final out = PodcastLibrary.applyKeepLatest(merged);
      expect(out.map((e) => e.id), ['a3', 'b2', 'b1']);
      expect(PodcastLibrary.isArchived('a1'), isTrue);
      await PodcastLibrary.setShowKeepLatest(feedA, 3);
      expect(PodcastLibrary.isArchived('a1'), isFalse);
      expect(PodcastLibrary.applyKeepLatest(merged), hasLength(5));
    });

    test('mark all as listened and undo', () async {
      await Hive.box('PodcastProgress')
          .put('e1', {'id': 'e1', 'positionMs': 60000, 'durationMs': 600000});
      await Hive.box('PodcastPlayed').put('e3', 1);
      final snap = PodcastLibrary.markAllListened([ep('e1'), ep('e2'), ep('e3')]);
      expect(snap.ids, ['e1', 'e2']);
      expect(Hive.box('PodcastPlayed').keys.toSet(), {'e1', 'e2', 'e3'});
      expect(Hive.box('PodcastProgress').get('e1'), isNull);
      await PodcastLibrary.undoMarkAll(snap);
      expect(Hive.box('PodcastPlayed').keys.toSet(), {'e3'});
      expect((Hive.box('PodcastProgress').get('e1') as Map)['positionMs'], 60000);
    });
  });
}
