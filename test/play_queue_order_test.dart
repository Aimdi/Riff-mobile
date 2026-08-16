import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
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

  test('volumeIconFor maps mute / low / high', () {
    expect(volumeIconFor(0), Icons.volume_off);
    expect(volumeIconFor(20), Icons.volume_down);
    expect(volumeIconFor(50), Icons.volume_up);
    expect(volumeIconFor(100), Icons.volume_up);
  });

  test('play next is a no-op when the song is current or already next', () {
    expect(
      isPlayNextNoOp(
        songId: 'a',
        queueIds: ['a', 'b'],
        currentIndex: 0,
      ),
      isTrue,
    );
    expect(
      isPlayNextNoOp(
        songId: 'b',
        queueIds: ['a', 'b'],
        currentIndex: 0,
      ),
      isTrue,
    );
    expect(
      isPlayNextNoOp(
        songId: 'c',
        queueIds: ['a', 'b'],
        currentIndex: 0,
      ),
      isFalse,
    );
  });

  test('radio continuation keeps radio when the queue is empty', () {
    expect(
      shouldKeepRadioWhenEnqueueing(radioOn: true, queueEmpty: true),
      isTrue,
    );
    expect(
      shouldKeepRadioWhenEnqueueing(radioOn: true, queueEmpty: false),
      isFalse,
    );
    expect(
      shouldKeepRadioWhenEnqueueing(radioOn: false, queueEmpty: true),
      isFalse,
    );
  });

  test('search tab play falls back to overview when the filter is empty', () {
    const a = MediaItem(id: 'a', title: 'A');
    expect(
      searchTabPlaySongs<MediaItem>(
        items: const [],
        filtered: const [],
        overview: [a],
      ).map((e) => e.id),
      ['a'],
    );
    expect(searchTabFallback(overview: [a]), [a]);
    expect(searchTabFallback(overview: const []), isEmpty);
  });

  test('skip on the last track retries instead of pausing', () {
    expect(
      shouldRetryInsteadOfSkip(hasNext: false, radioOn: false),
      isTrue,
    );
    expect(
      shouldRetryInsteadOfSkip(hasNext: true, radioOn: false),
      isFalse,
    );
    expect(
      shouldRetryInsteadOfSkip(hasNext: false, radioOn: true),
      isFalse,
    );
  });

  test('save queue is disabled when empty', () {
    expect(canSaveQueueAsPlaylist(0), isFalse);
    expect(canSaveQueueAsPlaylist(3), isTrue);
  });

  test('new playlist name uses the lead track and date for a queue', () {
    expect(defaultNewPlaylistName(songItems: const []), isEmpty);
    expect(
      defaultNewPlaylistName(songItems: [song('only')]),
      'only',
    );
    expect(
      defaultNewPlaylistName(
        songItems: [song('First'), song('Second')],
        now: DateTime(2026, 8, 16),
      ),
      'First · 2026-08-16',
    );
  });

  test('optimistic fav is kept while the same song is writing', () {
    expect(
      shouldKeepOptimisticFav(
        currentSongId: 'a',
        persistSongId: 'a',
      ),
      isTrue,
    );
    expect(
      shouldKeepOptimisticFav(
        currentSongId: 'a',
        persistSongId: 'b',
      ),
      isFalse,
    );
    expect(
      shouldKeepOptimisticFav(
        currentSongId: 'a',
        persistSongId: null,
      ),
      isFalse,
    );
  });
}
