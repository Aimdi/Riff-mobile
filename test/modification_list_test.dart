import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/modification_list.dart';

MediaItem _song(String id) => MediaItem(id: id, title: id);

void main() {
  group('rearrange rows keep their song\'s key', () {
    test('a moved song takes its key with it', () {
      final before = [_song('a'), _song('b'), _song('c')];
      final after = [_song('c'), _song('a'), _song('b')];
      Key keyOf(List<MediaItem> list, String id) =>
          rearrangeRowKey(list, list.indexWhere((s) => s.id == id));
      for (final id in ['a', 'b', 'c']) {
        expect(keyOf(after, id), keyOf(before, id));
      }
    });

    test('a song in the list twice gets a key per copy', () {
      final list = [_song('a'), _song('b'), _song('a')];
      final keys = [
        for (var i = 0; i < list.length; i++) rearrangeRowKey(list, i)
      ];
      expect(keys.toSet(), hasLength(3));
    });

    test('works on a list of any element type holding songs', () {
      final List<dynamic> list = [_song('a'), _song('b')];
      expect(rearrangeRowKey(list, 1), rearrangeRowKey([_song('b')], 0));
    });
  });
}
