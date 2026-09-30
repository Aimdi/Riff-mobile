import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/kugou_lyrics_service.dart';

Map<String, dynamic> song(String hash, dynamic duration) =>
    {'hash': hash, 'duration': duration};

void main() {
  test('closest duration first, each hash once, outside ±5 s dropped', () {
    final songs = [
      song('far', 300),
      song('plus4', 204),
      song('exact', 200),
      song('minus2', 198),
      song('exact', 200), // duplicate hash
      song('plus2', 202),
      song('six', 206),
    ];
    expect(KuGouLyricsService.songHashesByDuration(songs, 200),
        ['exact', 'minus2', 'plus2', 'plus4']);
  });

  test('skips malformed entries', () {
    final songs = [
      {'hash': 'nodur'},
      {'duration': 200},
      song('', 200),
      song('ok', 201),
    ];
    expect(KuGouLyricsService.songHashesByDuration(songs, 200), ['ok']);
  });

  test('empty when nothing within tolerance', () {
    expect(KuGouLyricsService.songHashesByDuration([song('a', 100)], 200),
        isEmpty);
  });
}
