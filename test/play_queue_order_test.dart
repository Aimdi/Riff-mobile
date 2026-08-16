import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/play_queue_order.dart';

void main() {
  MediaItem song(String id) => MediaItem(id: id, title: id);

  test('playQueueFrom copies and keeps order when not shuffled', () {
    final source = [song('a'), song('b'), song('c')];
    final queue = playQueueFrom(source, shuffle: false);
    expect(queue.map((e) => e.id), ['a', 'b', 'c']);
    queue.removeAt(0);
    expect(source.length, 3);
  });

  test('playQueueFrom shuffle does not mutate the source list', () {
    final source = [song('a'), song('b'), song('c'), song('d')];
    final queue = playQueueFrom(source, shuffle: true);
    expect(queue.length, 4);
    expect(queue.map((e) => e.id).toSet(), {'a', 'b', 'c', 'd'});
    expect(source.map((e) => e.id), ['a', 'b', 'c', 'd']);
  });

  test('library play bar is hidden in cloud mode or when empty', () {
    expect(
      shouldShowLibrarySongsPlayBar(cloudMode: true, songCount: 12),
      isFalse,
    );
    expect(
      shouldShowLibrarySongsPlayBar(cloudMode: false, songCount: 0),
      isFalse,
    );
    expect(
      shouldShowLibrarySongsPlayBar(cloudMode: false, songCount: 1),
      isTrue,
    );
  });

  test('discovery shelves play as a queue only with 2+ tracks', () {
    expect(shouldPlayDiscoveryShelfAsQueue(0), isFalse);
    expect(shouldPlayDiscoveryShelfAsQueue(1), isFalse);
    expect(shouldPlayDiscoveryShelfAsQueue(2), isTrue);
  });

  test('playNextBatchOrder reverses so inserts keep original order', () {
    expect(
      playNextBatchOrder([song('a'), song('b'), song('c')]).map((e) => e.id),
      ['c', 'b', 'a'],
    );
  });

  test('sleepEndLabelKey switches for long-form', () {
    expect(sleepEndLabelKey(longForm: false), 'endOfThisSong');
    expect(sleepEndLabelKey(longForm: true), 'endOfThisEpisode');
  });
}
