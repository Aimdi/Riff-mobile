import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_feed_url.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

void main() {
  group('a pasted feed address', () {
    test('http(s) links, trimmed', () {
      expect(podcastFeedUrlFrom('https://feeds.example.com/show.rss'),
          'https://feeds.example.com/show.rss');
      expect(podcastFeedUrlFrom('  http://example.com/feed?id=7  '),
          'http://example.com/feed?id=7');
    });

    test('subscribe links read as https', () {
      for (final link in [
        'feed://example.com/rss',
        'feed:https://example.com/rss',
        'pcast://example.com/rss',
        'itpc://example.com/rss',
        'podcast://example.com/rss',
      ]) {
        expect(podcastFeedUrlFrom(link), 'https://example.com/rss',
            reason: link);
      }
      expect(podcastFeedUrlFrom('feed:http://example.com/rss'),
          'http://example.com/rss');
    });

    test('not one: words, YouTube (channels), other schemes, no domain', () {
      for (final input in [
        '',
        'the daily',
        'daily',
        'https://www.youtube.com/@somechannel',
        'https://youtube.com/channel/UCabc',
        'https://music.youtube.com/playlist?list=PL1',
        'https://youtu.be/abc',
        'ftp://example.com/rss',
        'https://localhost/rss',
        'https://example.com/a feed',
      ]) {
        expect(podcastFeedUrlFrom(input), isNull, reason: input);
      }
    });
  });

  group("a feed's name, host and cover", () {
    test('from the channel, not its episodes', () {
      expect(parsePodcastFeedInfo('''<?xml version="1.0"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title> The Show </title>
    <itunes:author>Host Name</itunes:author>
    <itunes:image href="https://example.com/cover.jpg"/>
    <item><title>Episode 1</title></item>
  </channel>
</rss>'''), {
        'title': 'The Show',
        'author': 'Host Name',
        'artwork': 'https://example.com/cover.jpg',
      });
    });

    test('the owner and the RSS image when that is all there is', () {
      expect(
          parsePodcastFeedInfo(
              '''<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Private Feed</title>
    <itunes:owner><itunes:name>Owner</itunes:name></itunes:owner>
    <image><url>https://example.com/rss.png</url></image>
  </channel>
</rss>'''),
          {
            'title': 'Private Feed',
            'author': 'Owner',
            'artwork': 'https://example.com/rss.png',
          });
    });

    test('nothing for what is not a podcast feed', () {
      expect(parsePodcastFeedInfo('<rss><nochannel/></rss>'), isNull);
      expect(
          parsePodcastFeedInfo(
              '<rss><channel><title> </title></channel></rss>'),
          isNull);
      expect(() => parsePodcastFeedInfo('<html><body>Hi'), throwsA(anything));
    });
  });

  group('the result row', () {
    setUp(() async {
      await Hive.openBox('PodcastSubs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await Hive.close();
    });

    const show = {
      'title': 'Private Feed',
      'author': 'Owner',
      'artwork': '',
      'feedUrl': 'https://example.com/rss',
    };

    testWidgets('follows the show, and unfollows it with Undo', (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: PodcastFeedResultRow(show: show)),
      ));
      expect(find.text('Private Feed'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(PodcastService.isSubscribed('https://example.com/rss'), isTrue);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check_circle_rounded));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(PodcastService.isSubscribed('https://example.com/rss'), isFalse);
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.text('unsubscribedFrom'), findsOneWidget);
    });
  });
}
