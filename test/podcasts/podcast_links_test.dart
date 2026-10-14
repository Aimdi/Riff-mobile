import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_links.dart';
import 'package:harmonymusic/services/podcast_service.dart';

const _rss = '''<?xml version="1.0"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>The Show</title>
    <itunes:author>The Host</itunes:author>
    <itunes:image href="https://example.com/art.jpg"/>
  </channel>
</rss>''';

void main() {
  group('the link in shared text', () {
    test('a link, alone or among words, as written', () {
      expect(
          linkInText('https://youtu.be/abc?si=x'), 'https://youtu.be/abc?si=x');
      expect(
          linkInText('Listen to "The Show" https://podcasts.apple.com/us/'
              'podcast/the-show/id123 on Apple Podcasts'),
          'https://podcasts.apple.com/us/podcast/the-show/id123');
      expect(linkInText('pcast://http://example.com/feed.xml'),
          'pcast://http://example.com/feed.xml');
      expect(linkInText('riff://voice?q=jazz'), 'riff://voice?q=jazz');
    });

    test("a sentence's full stop or bracket isn't part of it", () {
      expect(linkInText('Here: https://example.com/feed.xml.'),
          'https://example.com/feed.xml');
      expect(
          linkInText('(https://example.com/feed)'), 'https://example.com/feed');
    });

    test('words without a link have none', () {
      expect(linkInText('my favourite podcast: the daily'), isNull);
      expect(linkInText('mypodcast:x'), isNull);
      expect(linkInText(''), isNull);
    });
  });

  group('podcast links', () {
    void isFeed(String link, String feed, {bool guessed = false}) {
      final p = podcastLinkFrom(link);
      expect(p?.feedUrl, feed, reason: link);
      expect(p?.appleId, isNull, reason: link);
      expect(p?.schemeGuessed, guessed, reason: link);
    }

    void isApple(String link, String id) {
      final p = podcastLinkFrom(link);
      expect(p?.appleId, id, reason: link);
      expect(p?.feedUrl, isNull, reason: link);
    }

    test('subscribe links name the feed, https when they don\'t say', () {
      isFeed(
          'pcast://http://example.com/feed.xml', 'http://example.com/feed.xml');
      isFeed(
          'feed:https://example.com/feed.xml', 'https://example.com/feed.xml');
      isFeed('itpc://example.com/feed.xml', 'https://example.com/feed.xml',
          guessed: true);
      isFeed('feed://example.com/feed.xml', 'https://example.com/feed.xml',
          guessed: true);
      isFeed('podcast://example.com/feed', 'https://example.com/feed',
          guessed: true);
      isFeed(
          'antennapod-subscribe://example.com/feed', 'https://example.com/feed',
          guessed: true);
    });

    test("Subscribe on Android's and AntennaPod's pages", () {
      isFeed('https://www.subscribeonandroid.com/feeds.megaphone.fm/abc',
          'https://feeds.megaphone.fm/abc',
          guessed: true);
      isFeed(
          'https://antennapod.org/deeplink/subscribe?'
              'url=https%3A%2F%2Fexample.com%2Ffeed&title=The%20Show',
          'https://example.com/feed');
    });

    test("a show on Apple Podcasts or Overcast, by Apple's id", () {
      isApple('https://podcasts.apple.com/us/podcast/the-daily/id1200361736',
          '1200361736');
      // An episode's link: its show.
      isApple(
          'https://podcasts.apple.com/gb/podcast/the-daily/id1200361736'
              '?i=1000600000000',
          '1200361736');
      isApple('https://itunes.apple.com/us/podcast/x/id123', '123');
      isApple('https://overcast.fm/itunes1200361736/the-daily', '1200361736');
    });

    test("an old Google Podcasts link carries the feed's address", () {
      final encoded =
          base64Url.encode(utf8.encode('https://feeds.example.com/show.xml'));
      isFeed('https://podcasts.google.com/feed/$encoded?sa=X',
          'https://feeds.example.com/show.xml');
    });

    test('anything else is no podcast link', () {
      for (final link in [
        'https://music.youtube.com/watch?v=abc',
        'https://example.com/feed.xml',
        'https://podcasts.apple.com/us/browse',
        'https://overcast.fm/+AbCdEf',
        'pcast://',
        'feed://youtube.com/channel/x',
        'riff://voice?q=jazz',
        'https://podcasts.google.com/feed/!!!',
      ]) {
        expect(podcastLinkFrom(link), isNull, reason: link);
      }
    });
  });

  group('the show a link names', () {
    late HttpServer server;
    late List<Uri> asked;
    final base = PodcastService.directoryBase;

    setUp(() async {
      asked = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        asked.add(req.uri);
        await req.drain<void>();
        if (req.uri.path == '/lookup') {
          final id = req.uri.queryParameters['id'];
          req.response.write(jsonEncode({
            'results': [
              if (id == '123')
                {
                  'collectionName': 'The Daily',
                  'artistName': 'The New York Times',
                  'artworkUrl600': 'https://example.com/600x600bb.jpg',
                  'feedUrl': 'https://feeds.example.com/daily',
                },
            ],
          }));
        } else if (req.uri.path == '/feed') {
          req.response.write(_rss);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      PodcastService.directoryBase = 'http://127.0.0.1:${server.port}';
    });
    tearDown(() async {
      PodcastService.directoryBase = base;
      await server.close(force: true);
    });

    test("Apple's: looked up in its directory", () async {
      final show = await podcastShowFor(const PodcastLink.apple('123'));
      expect(show?['title'], 'The Daily');
      expect(show?['author'], 'The New York Times');
      expect(show?['feedUrl'], 'https://feeds.example.com/daily');
      expect(asked.single.queryParameters['id'], '123');
      expect(await podcastShowFor(const PodcastLink.apple('999')), isNull);
    });

    test("a feed's: read from it, over http when https doesn't answer",
        () async {
      final http = 'http://127.0.0.1:${server.port}/feed';
      final show = await podcastShowFor(PodcastLink.feed(http));
      expect(show?['title'], 'The Show');
      expect(show?['feedUrl'], http);

      // The link didn't say: https first (no answer here), then http.
      final guessed = await podcastShowFor(PodcastLink.feed(
          'https://127.0.0.1:${server.port}/feed',
          schemeGuessed: true));
      expect(guessed?['feedUrl'], http);
      // It said https: that's the one.
      expect(
          await podcastShowFor(
              PodcastLink.feed('https://127.0.0.1:${server.port}/feed')),
          isNull);
    });
  });
}
