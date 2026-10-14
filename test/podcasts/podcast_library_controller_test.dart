import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/services/youtube_podcast_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library_controller.dart';

/// Podcast searches wait until the test answers them; channel searches
/// find nothing.
class _FakeMusic extends GetxService implements MusicServices {
  final pending = <String, Completer<Map<String, dynamic>>>{};

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) {
    if (filter != 'podcasts') return Future.value(<String, dynamic>{});
    return (pending[query] = Completer<Map<String, dynamic>>()).future;
  }

  void answer(String query, String showTitle) => pending[query]!.complete({
        'Podcasts': [
          Playlist(
              title: showTitle, playlistId: 'PL_$showTitle', thumbnailUrl: ''),
        ],
      });

  void fail(String query) => pending[query]!.completeError(Exception('down'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// YouTube's podcast endpoints, answering every request with an error.
Future<(HttpServer, List<String>)> _brokenYoutube() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final hits = <String>[];
  server.listen((req) async {
    hits.add(req.uri.path);
    await req.drain<void>();
    req.response.statusCode = 500;
    await req.response.close();
  });
  return (server, hits);
}

/// Apple's podcast directory: [shows] results for any search, titled
/// after its term ("Show 1 for daily"), plus one without a feed.
Future<(HttpServer, List<Uri>)> _directory({int shows = 3}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final asked = <Uri>[];
  server.listen((req) async {
    asked.add(req.uri);
    final term = req.uri.queryParameters['term'];
    final episodes = req.uri.queryParameters['entity'] == 'podcastEpisode';
    req.response.write(jsonEncode({
      'results': episodes
          ? [
              {
                'trackName': 'Episode for $term',
                'collectionName': 'Show 1 for $term',
                'feedUrl': 'https://feeds.example/1',
                'episodeUrl': 'https://cdn.example/1.mp3',
                'episodeGuid': 'e1',
              },
            ]
          : [
              {'collectionName': 'No feed for $term', 'artistName': 'Apple'},
              for (var i = 1; i <= shows; i++)
                {
                  'collectionName': 'Show $i for $term',
                  'artistName': 'Host $i',
                  'artworkUrl600': 'https://art.example/$i.jpg',
                  'feedUrl': 'https://feeds.example/$i',
                },
            ],
    }));
    await req.response.close();
  });
  return (server, asked);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final defaultYoutube = YoutubePodcastService.baseUrl;
  final defaultDirectory = PodcastService.directoryBase;
  late HttpServer server;
  late List<String> hits;
  late HttpServer directory;
  late List<Uri> asked;

  setUp(() async {
    Get.reset();
    (server, hits) = await _brokenYoutube();
    YoutubePodcastService.baseUrl = 'http://127.0.0.1:${server.port}';
    (directory, asked) = await _directory();
    PodcastService.directoryBase = 'http://127.0.0.1:${directory.port}';
  });

  tearDown(() async {
    YoutubePodcastService.baseUrl = defaultYoutube;
    PodcastService.directoryBase = defaultDirectory;
    await server.close(force: true);
    await directory.close(force: true);
    Get.reset();
  });

  group('search', () {
    test('an older search answering last does not replace a newer one',
        () async {
      final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
      final c = LibraryPodcastsController();

      final older = c.searchPodcasts('old query');
      final newer = c.searchPodcasts('new query');
      expect(c.isSearching.isTrue, isTrue);

      // The old search finishing must neither show its results nor stop
      // the spinner of the one still running.
      music.answer('old query', 'Old');
      await older;
      expect(c.searchResults, isEmpty);
      expect(c.isSearching.isTrue, isTrue);

      music.answer('new query', 'New');
      await newer;
      expect(c.searchResults.map((p) => p.title), ['New']);
      expect(c.directoryResults.first['title'], 'Show 1 for new query');
      expect(c.episodeResults.single['title'], 'Episode for new query');
      expect(c.isSearching.isFalse, isTrue);
      expect(c.searchQuery.value, 'new query');
    });

    test('clearing the field drops a search still running', () async {
      final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
      final c = LibraryPodcastsController();

      final running = c.searchPodcasts('some show');
      c.clearSearch();
      music.answer('some show', 'Late');
      await running;
      expect(c.searchResults, isEmpty);
      expect(c.directoryResults, isEmpty);
      expect(c.episodeResults, isEmpty);
      expect(c.hasSearched.isFalse, isTrue);
      expect(c.isSearching.isFalse, isTrue);
    });

    test("the directory's shows come with YouTube's: those with a feed",
        () async {
      final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
      final c = LibraryPodcastsController();

      final search = c.searchPodcasts('daily');
      music.answer('daily', 'From YouTube');
      await search;
      expect(c.searchResults.map((p) => p.title), ['From YouTube']);
      expect(c.directoryResults, [
        for (var i = 1; i <= 3; i++)
          {
            'title': 'Show $i for daily',
            'author': 'Host $i',
            'artwork': 'https://art.example/$i.jpg',
            'feedUrl': 'https://feeds.example/$i',
          },
      ]);
      final query = asked
          .singleWhere((u) => !u.queryParameters.containsKey('entity'))
          .queryParameters;
      expect(query['media'], 'podcast');
      expect(query['term'], 'daily');
      expect(query['country'], isNotEmpty);
      // And its episodes.
      expect(c.episodeResults.single['title'], 'Episode for daily');
      expect(c.episodeResults.single['id'], 'podcast_${'e1'.hashCode}');
    });

    test('the first ten of them, even when YouTube fails', () async {
      await directory.close(force: true);
      (directory, asked) = await _directory(shows: 25);
      PodcastService.directoryBase = 'http://127.0.0.1:${directory.port}';
      final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
      final c = LibraryPodcastsController();

      final search = c.searchPodcasts('news');
      music.fail('news');
      await search;
      expect(c.searchResults, isEmpty);
      expect(c.directoryResults.map((s) => s['title']),
          [for (var i = 1; i <= 10; i++) 'Show $i for news']);
      expect(c.episodeResults.single['title'], 'Episode for news');
      expect(c.isSearching.isFalse, isTrue);
    });

    test('none when the directory is out of reach', () async {
      await directory.close(force: true);
      final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
      final c = LibraryPodcastsController();

      final search = c.searchPodcasts('daily');
      music.answer('daily', 'From YouTube');
      await search;
      expect(c.searchResults.map((p) => p.title), ['From YouTube']);
      expect(c.directoryResults, isEmpty);
      expect(c.episodeResults, isEmpty);
    });
  });

  group('YouTube popular rows', () {
    test('an empty load is not refetched on every rebuild', () async {
      final c = LibraryPodcastsController();
      await c.loadYoutubePodcasts();
      await _settle();
      // Shows + episodes: one request each.
      expect(hits, hasLength(2));
      expect(c.ytPopularShows, isEmpty);

      // The Discover view asks again after each rebuild with empty rows.
      for (var i = 0; i < 5; i++) {
        await c.loadYoutubePodcasts();
      }
      await _settle();
      expect(hits, hasLength(2));
      expect(c.isYtLoading.isFalse, isTrue);
    });

    test('a forced load still goes out', () async {
      final c = LibraryPodcastsController();
      await c.loadYoutubePodcasts();
      await c.loadYoutubePodcasts(force: true);
      await _settle();
      expect(hits, hasLength(4));
    });
  });
}
