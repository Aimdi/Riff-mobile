import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Search/search_play_top.dart';

void main() {
  test('songsFromSearchResult reads the Songs bucket', () {
    const song = MediaItem(id: 'a', title: 'A');
    expect(
      songsFromSearchResult({
        'Songs': [song]
      }).map((e) => e.id),
      ['a'],
    );
    expect(songsFromSearchResult(const {}), isEmpty);
    expect(
      songsFromSearchResult({
        'Songs': ['not-a-song']
      }),
      isEmpty,
    );
  });

  test('Enter opens the results and plays nothing', () {
    var opened = '';
    var remembered = '';
    submitSearchQuery(
      ' radiohead ',
      onLink: (_) => fail('not a link'),
      onOpenResults: (q) => opened = q,
      onRemember: (q) => remembered = q,
    );
    expect(opened, 'radiohead');
    expect(remembered, 'radiohead');
  });

  test('a link is opened, not searched', () {
    var link = '';
    submitSearchQuery(
      'https://music.youtube.com/watch?v=abc',
      onLink: (t) => link = t,
      onOpenResults: (_) => fail('no results for a link'),
      onRemember: (_) => fail('a link is not remembered'),
    );
    expect(link, 'https://music.youtube.com/watch?v=abc');
  });

  test('an empty query does nothing', () {
    submitSearchQuery(
      '   ',
      onLink: (_) => fail('no link'),
      onOpenResults: (_) => fail('no results'),
      onRemember: (_) => fail('nothing remembered'),
    );
  });
}
