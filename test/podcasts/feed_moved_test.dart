import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';

String _feed(String title, List<String> episodes,
        {String? movedTo, String about = ''}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>$title</title>
  <description>$about</description>
  ${movedTo == null ? '' : '<itunes:new-feed-url>$movedTo</itunes:new-feed-url>'}
  ${episodes.map((e) => '<item><title>$e</title><guid>$e</guid>'
        '<enclosure url="https://example.com/$e.mp3"/></item>').join()}
</channel>
</rss>''';

void main() {
  test('where a show that moved says its feed is now', () {
    expect(
        feedMovedTo('<itunes:new-feed-url>https://new.example/feed?a=1&amp;b=2'
            '</itunes:new-feed-url>'),
        'https://new.example/feed?a=1&b=2');
    expect(
        feedMovedTo('<itunes:new-feed-url><![CDATA[ https://new.example/f ]]>'
            '</itunes:new-feed-url>'),
        'https://new.example/f');
    expect(feedMovedTo(_feed('Show', ['Ep 1'])), isNull);
    expect(feedMovedTo('<itunes:new-feed-url>ftp://x</itunes:new-feed-url>'),
        isNull);
  });

  group('over the network', () {
    late HttpServer server;
    late String base;
    final served = <String, String>{};

    setUp(() async {
      served.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) {
        final body = served[req.uri.path];
        if (body == null) {
          req.response.statusCode = HttpStatus.notFound;
        } else {
          req.response.write(body);
        }
        req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test(
        "a show that moved is read at its new feed, episodes kept as they "
        "were", () async {
      served['/old'] = _feed('Show', ['Ep 1'], movedTo: '$base/new');
      served['/new'] = _feed('Show', ['Ep 2', 'Ep 1']);
      final eps = await PodcastService.episodes('$base/old', 'Show', '');
      expect(eps.map((e) => e['title']), ['Ep 2', 'Ep 1']);
      // Same guid, same episode: its progress and played state stay.
      expect(eps[1]['id'], 'podcast_${'Ep 1'.hashCode}');
    });

    test("the show's page gets what its feed says about it", () async {
      served['/old'] =
          _feed('Show', ['Ep 1'], movedTo: '$base/new', about: 'Old words');
      served['/new'] = _feed('Show', ['Ep 2'], about: 'A show about shows');
      final feed = await PodcastService.feed('$base/old', 'Show', '');
      expect(feed.about, 'A show about shows');
      expect(feed.episodes.single['title'], 'Ep 2');
    });

    test("at its old feed still when the new one can't be read", () async {
      served['/old'] = _feed('Show', ['Ep 1'], movedTo: '$base/gone');
      final eps = await PodcastService.episodes('$base/old', 'Show', '');
      expect(eps.map((e) => e['title']), ['Ep 1']);
    });

    test('following a show by its old address keeps the new one', () async {
      served['/old'] = _feed('Show', ['Ep 1'], movedTo: '$base/new');
      served['/new'] = _feed('New Show', ['Ep 2']);
      final info = await PodcastService.feedInfo('$base/old');
      expect(info?['feedUrl'], '$base/new');
      expect(info?['title'], 'New Show');
    });
  });
}
