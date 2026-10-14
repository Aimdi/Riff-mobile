import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/widgets/podcast_play.dart';

class _FakePlayer extends GetxController implements PlayerController {
  List<MediaItem>? played;
  int? at;

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    played = mediaItems;
    at = index;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One of Apple's episode search results.
Map<String, dynamic> _result(
        {String? guid = 'ep-42',
        String url = 'https://cdn.example/42.mp3',
        String? feed = 'https://feeds.example/show'}) =>
    {
      'wrapperType': 'podcastEpisode',
      'kind': 'podcast-episode',
      'trackName': 'Episode 42: Ada',
      'collectionName': 'The Show',
      if (feed != null) 'feedUrl': feed,
      'episodeUrl': url,
      if (guid != null) 'episodeGuid': guid,
      'artworkUrl600': 'https://art.example/600.jpg',
      'releaseDate': '2026-03-05T10:00:00Z',
      'trackTimeMillis': 2712000,
      'description': '<p>We talk to <b>Ada</b>.</p><p>More soon.</p>',
    };

String _feed(List<String> items) => '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">
<channel>
  <title>The Show</title>
  ${items.join('\n')}
</channel>
</rss>''';

String _item(String title, {String? guid, String? url, String? chapters}) =>
    '<item><title>$title</title>'
    '${guid == null ? '' : '<guid>$guid</guid>'}'
    '<enclosure url="${url ?? 'https://cdn.example/$title.mp3'}"/>'
    '${chapters == null ? '' : '<podcast:chapters url="$chapters"/>'}'
    '</item>';

void main() {
  group('an episode the directory found', () {
    test('kept as its feed keeps it, with the id it has there', () {
      final e = directoryEpisode(_result())!;
      expect(e['id'], 'podcast_${'ep-42'.hashCode}');
      expect(e['title'], 'Episode 42: Ada');
      expect(e['show'], 'The Show');
      expect(e['feedUrl'], 'https://feeds.example/show');
      expect(e['url'], 'https://cdn.example/42.mp3');
      expect(e['artwork'], 'https://art.example/600.jpg');
      expect(e['description'], contains('We talk to Ada.'));
      expect(e['description'], isNot(contains('<')));
      expect(e['date'], '5 Mar 2026');
      expect(
          e['pubDateMs'], DateTime.utc(2026, 3, 5, 10).millisecondsSinceEpoch);
      expect(e['durationSec'], 2712);

      // The same id its feed gives it: progress, played state and its
      // download are one.
      final fromFeed = parsePodcastFeed(
          _feed([_item('Episode 42', guid: 'ep-42')]), 'The Show', '');
      expect(fromFeed.single['id'], e['id']);
    });

    test('without a guid, told apart by its audio as its feed does', () {
      final e = directoryEpisode(_result(guid: null))!;
      final fromFeed = parsePodcastFeed(
          _feed([_item('Episode 42', url: 'https://cdn.example/42.mp3')]),
          'The Show',
          '');
      expect(e['id'], fromFeed.single['id']);
    });

    test('none without its audio or its show\'s feed', () {
      expect(directoryEpisode(_result(url: '')), isNull);
      expect(directoryEpisode(_result(url: 'ftp://cdn.example/1.mp3')), isNull);
      expect(directoryEpisode(_result(feed: null)), isNull);
    });
  });

  group('over the network', () {
    final defaultDirectory = PodcastService.directoryBase;
    late HttpServer server;
    late String base;
    final served = <String, String>{};
    final asked = <Uri>[];

    setUp(() async {
      served.clear();
      asked.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      PodcastService.directoryBase = base;
      server.listen((req) {
        asked.add(req.uri);
        final body = served[req.uri.path];
        if (body == null) {
          req.response.statusCode = HttpStatus.notFound;
        } else {
          req.response.write(body);
        }
        req.response.close();
      });
    });
    tearDown(() async {
      PodcastService.directoryBase = defaultDirectory;
      await server.close(force: true);
      Get.reset();
    });

    test('the search asks for episodes, keeps the first ten it can play',
        () async {
      served['/search'] = jsonEncode({
        'results': [
          _result(url: ''),
          for (var i = 1; i <= 12; i++)
            {..._result(guid: 'g$i'), 'trackName': 'Episode $i'},
          _result(feed: null),
        ],
      });
      final found = await PodcastService.searchEpisodes('ada');
      expect(found.map((e) => e['title']),
          [for (var i = 1; i <= 10; i++) 'Episode $i']);
      final query = asked.single.queryParameters;
      expect(query['entity'], 'podcastEpisode');
      expect(query['media'], 'podcast');
      expect(query['term'], 'ada');
      expect(query['limit'], '15');
      expect(query['country'], isNotEmpty);
    });

    test('none when the directory is out of reach', () async {
      expect(await PodcastService.searchEpisodes('ada'), isEmpty);
    });

    test("played from its show's feed: whole, the show's episodes after it",
        () async {
      served['/feed'] = _feed([
        _item('Episode 43', guid: 'ep-43'),
        _item('Episode 42', guid: 'ep-42', chapters: '$base/ch42.json'),
        _item('Episode 41', guid: 'ep-41'),
      ]);
      final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
      expect(
          await playDirectoryEpisode(
              directoryEpisode(_result(feed: '$base/feed'))!),
          isTrue);
      expect(player.played!.map((e) => e.title),
          ['Episode 43', 'Episode 42', 'Episode 41']);
      expect(player.at, 1);
      final playing = player.played![1];
      expect(playing.id, 'podcast_${'ep-42'.hashCode}');
      expect(playing.artist, 'The Show');
      expect(playing.extras?['chaptersUrl'], '$base/ch42.json');
      expect(playing.extras?['feedUrl'], '$base/feed');
      expect(playing.extras?['isPodcast'], isTrue);
    });

    test("as found when its feed doesn't have it, or can't be read", () async {
      final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
      served['/feed'] = _feed([_item('Something else', guid: 'other')]);
      for (final feed in ['$base/feed', '$base/gone']) {
        player.played = null;
        expect(
            await playDirectoryEpisode(directoryEpisode(_result(feed: feed))!),
            isTrue);
        final playing = player.played!.single;
        expect(player.at, 0);
        expect(playing.id, 'podcast_${'ep-42'.hashCode}');
        expect(playing.title, 'Episode 42: Ada');
        expect(playing.artist, 'The Show');
        expect(playing.duration, const Duration(seconds: 2712));
        expect(playing.extras?['url'], 'https://cdn.example/42.mp3');
        expect(playing.extras?['feedUrl'], feed);
        expect(playing.extras?['isPodcast'], isTrue);
      }
    });
  });
}
