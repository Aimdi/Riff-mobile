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
}
