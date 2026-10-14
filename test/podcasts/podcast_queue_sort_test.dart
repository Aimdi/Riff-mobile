import 'dart:math';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:hive/hive.dart';

MediaItem _episode(String id,
        {String show = 'Show', int? released, int? minutes, String? date}) =>
    MediaItem(
      id: id,
      title: id,
      artist: show,
      duration: minutes == null ? null : Duration(minutes: minutes),
      extras: {
        'isPodcast': true,
        'url': 'https://cdn.example/$id.mp3',
        if (released != null) 'pubDateMs': released,
        if (date != null) 'date': date,
      },
    );

int _day(int d) => DateTime.utc(2026, 3, d).millisecondsSinceEpoch;

List<String> _ids(Iterable<MediaItem> items) => [for (final e in items) e.id];

void main() {
  final queue = [
    _episode('b', show: 'Beta', released: _day(3), minutes: 60),
    _episode('a1', show: 'alpha', released: _day(1), minutes: 20),
    _episode('none', show: 'Beta'),
    _episode('a2', show: 'Alpha', released: _day(5), minutes: 45),
    _episode('c', show: 'Gamma', released: _day(3), minutes: 20),
  ];

  test('by date and by length; what has none goes last, ties as they were', () {
    expect(_ids(sortedQueue(queue, PodcastQueueSort.newest)),
        ['a2', 'b', 'c', 'a1', 'none']);
    expect(_ids(sortedQueue(queue, PodcastQueueSort.oldest)),
        ['a1', 'b', 'c', 'a2', 'none']);
    expect(_ids(sortedQueue(queue, PodcastQueueSort.shortest)),
        ['a1', 'c', 'a2', 'b', 'none']);
    expect(_ids(sortedQueue(queue, PodcastQueueSort.longest)),
        ['b', 'a2', 'a1', 'c', 'none']);
  });

  test('by show: each show together, its episodes as they were', () {
    expect(_ids(sortedQueue(queue, PodcastQueueSort.show)),
        ['a1', 'a2', 'b', 'none', 'c']);
  });

  test('shuffled: all of them, in another order', () {
    final shuffled =
        sortedQueue(queue, PodcastQueueSort.shuffle, random: Random(7));
    expect(_ids(shuffled).toSet(), _ids(queue).toSet());
    expect(shuffled, hasLength(queue.length));
    expect(_ids(shuffled), isNot(_ids(queue)));
  });

  test("an episode queued without its date in ms is read from the date shown",
      () {
    expect(queuedEpisodeReleasedMs(_episode('x', date: '5 Mar 2026')),
        DateTime.utc(2026, 3, 5).millisecondsSinceEpoch);
    expect(queuedEpisodeReleasedMs(_episode('y', date: '3 days ago')), 0);
    expect(queuedEpisodeReleasedMs(_episode('z')), 0);
  });

  group('the queue', () {
    late PodcastQueueController controller;

    setUp(() async {
      await Hive.openBox('PodcastQueue', bytes: Uint8List(0));
      controller = PodcastQueueController()..onInit();
    });
    tearDown(() => Hive.box('PodcastQueue').close());

    test('sorted, kept so, and Undo puts it back as it was', () {
      queue.forEach(controller.add);
      final undo = controller.sortUndoable(PodcastQueueSort.newest);
      expect(_ids(controller.queue), ['a2', 'b', 'c', 'a1', 'none']);
      // Stored sorted, dates and all.
      final again = PodcastQueueController()..onInit();
      expect(_ids(again.queue), _ids(controller.queue));
      expect(again.queue.first.extras?['pubDateMs'], _day(5));

      // Removed since stays removed; queued since comes after.
      controller.removeById('c');
      controller.add(_episode('new'));
      undo!();
      expect(_ids(controller.queue), ['b', 'a1', 'none', 'a2', 'new']);
    });

    test('one episode or none: nothing to sort', () {
      expect(controller.sortUndoable(PodcastQueueSort.oldest), isNull);
      controller.add(queue.first);
      expect(controller.sortUndoable(PodcastQueueSort.oldest), isNull);
    });
  });
}
