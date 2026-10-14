import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/long_form_queue.dart';

MediaItem _ep(int i, {String notes = ''}) => MediaItem(
    id: 'ep$i', title: 'Episode $i', extras: {'isPodcast': true, 'description': notes});

void main() {
  test('small shows keep every episode and the index', () {
    final items = [for (var i = 0; i < 30; i++) _ep(i)];
    final q = prepareLongFormQueue(items, 7);
    expect(q.items.length, 30);
    expect(q.index, 7);
  });

  test('huge shows send a window around the chosen episode', () {
    final items = [for (var i = 0; i < 3000; i++) _ep(i)];
    final q = prepareLongFormQueue(items, 1500, max: 120);
    expect(q.items.length, 120);
    expect(q.items[q.index].id, 'ep1500');
    expect(q.index, 10);

    final first = prepareLongFormQueue(items, 0, max: 120);
    expect(first.index, 0);
    expect(first.items.first.id, 'ep0');

    final last = prepareLongFormQueue(items, 2999, max: 120);
    expect(last.items.length, 120);
    expect(last.items[last.index].id, 'ep2999');
  });

  test('long notes are shortened in the queue but kept in full', () {
    final long = 'x' * 5000;
    final q = prepareLongFormQueue([_ep(1, notes: long), _ep(2, notes: 'short')], 0,
        notesMax: 600);
    expect((q.items[0].extras!['description'] as String).length, lessThan(700));
    expect(episodeNotes(q.items[0]), long);
    expect(episodeNotes(q.items[1]), 'short');
    expect(q.items[0].extras!['isPodcast'], isTrue);
  });

  test("chapters a feed gave inline stay out of the queue's copy, kept whole",
      () {
    final inline = 'data:application/json;base64,${'A' * 2000}';
    const short = 'data:application/json;base64,AAAA';
    const file = 'https://example.com/chapters.json';
    MediaItem withChapters(int i, String url) => MediaItem(
        id: 'ch$i',
        title: 'Episode $i',
        extras: {'isPodcast': true, 'chaptersUrl': url});
    final q = prepareLongFormQueue([
      withChapters(1, inline),
      withChapters(2, short),
      withChapters(3, file),
    ], 0);
    expect(q.items[0].extras!.containsKey('chaptersUrl'), isFalse);
    expect(episodeChaptersUrl(q.items[0]), inline);
    expect(q.items[0].extras!['isPodcast'], isTrue);
    expect(episodeChaptersUrl(q.items[1]), short);
    expect(q.items[1].extras!['chaptersUrl'], short);
    expect(q.items[2].extras!['chaptersUrl'], file);
  });
}
