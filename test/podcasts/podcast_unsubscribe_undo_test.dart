import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_folder_controller.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_unsub_undo_');
    Hive.init(tmp.path);
    await Hive.openBox('PodcastSubs');
    await Hive.openBox('PodcastFolders');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('a subscription comes back as it was, date included', () async {
    const feed = 'https://example.com/feed.xml';
    await PodcastService.subscribe({
      'title': 'Show',
      'author': 'Host',
      'artwork': 'https://example.com/art.jpg',
      'feedUrl': feed,
    });
    final before = Map<String, dynamic>.from(Hive.box('PodcastSubs').get(feed));

    final stored = await PodcastService.unsubscribe(feed);
    expect(PodcastService.isSubscribed(feed), isFalse);
    expect(stored, before);

    await PodcastService.restoreSubscription(stored!);
    expect(PodcastService.isSubscribed(feed), isTrue);
    expect(
        Map<String, dynamic>.from(Hive.box('PodcastSubs').get(feed)), before);
  });

  test('unsubscribing from a show that was never followed: nothing to undo',
      () async {
    expect(await PodcastService.unsubscribe('https://example.com/no'), isNull);
  });

  test('the show goes back into its folders at the same places', () {
    final c = PodcastFolderController();
    c.folders.assignAll([
      PodcastFolder('a', 'News', ['x', 'show', 'y']),
      PodcastFolder('b', 'Comedy', ['show']),
      PodcastFolder('c', 'Tech', ['z']),
    ]);

    final places = c.removeEverywhere('show');
    expect(places, {'a': 1, 'b': 0});
    expect(c.findById('a')!.podcastIds, ['x', 'y']);
    expect(c.findById('b')!.podcastIds, isEmpty);

    c.putBack('show', places);
    expect(c.findById('a')!.podcastIds, ['x', 'show', 'y']);
    expect(c.findById('b')!.podcastIds, ['show']);
    expect(c.findById('c')!.podcastIds, ['z']);
  });

  test('a folder deleted or changed meanwhile is handled', () {
    final c = PodcastFolderController();
    c.folders.assignAll([
      PodcastFolder('a', 'News', ['show', 'x']),
      PodcastFolder('b', 'Comedy', ['show']),
    ]);
    final places = c.removeEverywhere('show');
    c.folders.removeWhere((f) => f.id == 'b');
    c.findById('a')!.podcastIds.clear();

    c.putBack('show', places);
    expect(c.findById('a')!.podcastIds, ['show']);
    expect(c.findById('b'), isNull);
  });
}
