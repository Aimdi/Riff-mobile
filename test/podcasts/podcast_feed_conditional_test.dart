import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:hive/hive.dart';

String _feed(List<String> titles) => '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
  <title>Show</title>
  <description>About the show</description>
${[
      for (final t in titles)
        '''  <item>
    <title>$t</title>
    <guid>$t</guid>
    <enclosure url="https://example.com/$t.mp3"/>
  </item>'''
    ].join('\n')}
</channel>
</rss>''';

/// Feeds asked only whether they changed, as AntennaPod asks: what the
/// server said of a feed last time (ETag, Last-Modified) goes with the next
/// request, and a 304 is read as the feed was.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late String url;
  // What the server holds, and what it says of it.
  var titles = ['Ep 2', 'Ep 1'];
  String? etag;
  String? lastModified;
  final asked = <Map<String, String?>>[];
  var sent = 0;

  setUp(() async {
    // Real sockets to the local server below (the test binding fakes HTTP).
    HttpOverrides.global = null;
    await Hive.openBox(PodcastService.feedMemoBox, bytes: Uint8List(0));
    PodcastService.forgetFeedsInMemory();
    titles = ['Ep 2', 'Ep 1'];
    etag = '"v1"';
    lastModified = null;
    asked.clear();
    sent = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/feed.xml';
    server.listen((request) async {
      final ifNoneMatch = request.headers.value('if-none-match');
      final ifModifiedSince = request.headers.value('if-modified-since');
      asked.add(
          {'if-none-match': ifNoneMatch, 'if-modified-since': ifModifiedSince});
      final response = request.response;
      final unchanged = (ifNoneMatch != null && ifNoneMatch == etag) ||
          (ifModifiedSince != null && ifModifiedSince == lastModified);
      if (unchanged) {
        response.statusCode = HttpStatus.notModified;
      } else {
        if (etag != null) response.headers.set('etag', etag!);
        if (lastModified != null) {
          response.headers.set('last-modified', lastModified!);
        }
        response.headers.contentType = ContentType('application', 'rss+xml');
        response.write(_feed(titles));
        sent++;
      }
      await response.close();
    });
  });

  tearDown(() async {
    PodcastService.now = DateTime.now;
    PodcastService.forgetFeedsInMemory();
    await server.close(force: true);
    await Hive.close();
  });

  Future<List<String>> inbox() async => [
        for (final e
            in await PodcastService.episodes(url, 'Show', '', maxItems: 12))
          '${e['title']}'
      ];

  test('unchanged (ETag): asked once in full, then only whether it changed',
      () async {
    expect(await inbox(), ['Ep 2', 'Ep 1']);
    expect(await inbox(), ['Ep 2', 'Ep 1']);
    expect(sent, 1);
    expect(asked[0]['if-none-match'], isNull);
    expect(asked[1]['if-none-match'], '"v1"');
  });

  test('unchanged by its date (Last-Modified) too', () async {
    etag = null;
    lastModified = 'Wed, 14 Oct 2026 10:00:00 GMT';
    await inbox();
    expect(await inbox(), ['Ep 2', 'Ep 1']);
    expect(sent, 1);
    expect(asked[1]['if-modified-since'], lastModified);
  });

  test('changed: the new episodes, and asked about its new ETag after',
      () async {
    await inbox();
    titles = ['Ep 3', 'Ep 2', 'Ep 1'];
    etag = '"v2"';
    expect(await inbox(), ['Ep 3', 'Ep 2', 'Ep 1']);
    expect(await inbox(), ['Ep 3', 'Ep 2', 'Ep 1']);
    expect(sent, 2);
    expect(asked.last['if-none-match'], '"v2"');
  });

  test('a server saying nothing of it: asked in full each time, as before',
      () async {
    etag = null;
    await inbox();
    await inbox();
    expect(sent, 2);
    expect(asked.every((a) => a.values.every((v) => v == null)), isTrue);
  });

  test('the Inbox\'s feeds are remembered across starts', () async {
    await inbox();
    // Riff closed and started again: memory empty, the box kept.
    PodcastService.forgetFeedsInMemory();
    expect(await inbox(), ['Ep 2', 'Ep 1']);
    expect(sent, 1);
    expect(asked[1]['if-none-match'], '"v1"');

    // A show's page reads the whole feed: kept in memory only.
    await PodcastService.episodes(url, 'Show', '');
    PodcastService.forgetFeedsInMemory();
    await PodcastService.episodes(url, 'Show', '');
    expect(asked.last['if-none-match'], isNull);
  });

  test('read in full again a week on, whatever the server says', () async {
    await inbox();
    final weekOn = DateTime.now().add(PodcastService.feedMemoMaxAge);
    PodcastService.now = () => weekOn;
    await inbox();
    expect(asked.last['if-none-match'], isNull);
    expect(sent, 2);
  });

  test('what callers do to the episodes doesn\'t change what\'s remembered',
      () async {
    final first = await PodcastService.episodes(url, 'Show', '', maxItems: 12);
    first.first['title'] = 'Changed';
    final again = await PodcastService.episodes(url, 'Show', '', maxItems: 12);
    again.first['title'] = 'Changed again';
    expect(await inbox(), ['Ep 2', 'Ep 1']);
  });
}
