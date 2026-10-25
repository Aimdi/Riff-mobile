import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_inbox_counts.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';
import 'package:hive/hive.dart';

MediaItem _ep(String id) => MediaItem(
    id: id,
    title: 'Episode $id',
    artist: 'The Long Way Round',
    artUri: Uri.parse('https://example.com/$id.jpg'),
    extras: {'isPodcast': true, 'feedUrl': 'https://example.com/feed'});

HomeShelfData? _newEpisodes() {
  for (final s in riffPersonalShelves()) {
    if (s.id == 'riff:newEpisodes') return s;
  }
  return null;
}

void main() {
  setUp(() async {
    await Hive.openBox('PodcastPlayed', bytes: Uint8List(0));
  });
  tearDown(() async {
    PodcastInboxCounts.setInbox(const []);
    await Hive.close();
  });

  test("the Inbox's unplayed episodes, newest first, as Home's shelf",
      () async {
    await Hive.box('PodcastPlayed').put('b', true);
    PodcastInboxCounts.setInbox([_ep('a'), _ep('b'), _ep('c')]);
    final shelf = _newEpisodes()!;
    expect(shelf.title, 'newEpisodes');
    expect(shelf.items.map((i) => i.key), [homeSongKey('a'), homeSongKey('c')]);
  });

  test('no more than a shelf holds; the rest wait in the Inbox', () {
    PodcastInboxCounts.setInbox([for (var i = 0; i < 20; i++) _ep('e$i')]);
    expect(_newEpisodes()!.items.length, homeNewEpisodesMax);
  });

  test('nothing new: no shelf', () async {
    PodcastInboxCounts.setInbox(const []);
    expect(_newEpisodes(), isNull);
    await Hive.box('PodcastPlayed').put('a', true);
    PodcastInboxCounts.setInbox([_ep('a')]);
    expect(_newEpisodes(), isNull);
  });

  test('an episode you started stays in Jump back in only', () {
    PodcastInboxCounts.setInbox([_ep('a'), _ep('c')]);
    final sections = buildHomeSections(HomeFeedInput(
      // Two tiles: the grid would drop a lone one to keep its rows even.
      jumpBackIn: [
        HomeItem(homeSongKey('a'), _ep('a')),
        HomeItem(homeSongKey('x'), _ep('x')),
      ],
      personalized: [_newEpisodes()!],
    ));
    final shelf = sections
        .firstWhere((m) => m.section == HomeSection.personalized)
        .shelves
        .single;
    expect(shelf.items.map((i) => i.key), [homeSongKey('c')]);
  });
}
