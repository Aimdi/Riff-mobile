import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
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

  void answer(String query, String showTitle) =>
      pending[query]!.complete({
        'Podcasts': [
          Playlist(
              title: showTitle,
              playlistId: 'PL_$showTitle',
              thumbnailUrl: ''),
        ],
      });

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

void main() {
  final defaultYoutube = YoutubePodcastService.baseUrl;
  late HttpServer server;
  late List<String> hits;

  setUp(() async {
    Get.reset();
    (server, hits) = await _brokenYoutube();
    YoutubePodcastService.baseUrl = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    YoutubePodcastService.baseUrl = defaultYoutube;
    await server.close(force: true);
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
      expect(c.hasSearched.isFalse, isTrue);
      expect(c.isSearching.isFalse, isTrue);
    });
  });
}
