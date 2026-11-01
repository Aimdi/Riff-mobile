import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/hive_boxes.dart';
import 'package:hive/hive.dart';

Map<String, dynamic> _song(String id) => {'videoId': id, 'title': 'Song $id'};

List<String> _ids(Iterable<Map> songs) =>
    [for (final s in songs) '${s['videoId']}'];

void main() {
  late Box box;
  setUp(() async {
    box = await Hive.openBox(HiveBoxes.libFav, bytes: Uint8List(0));
  });
  tearDown(() async => Hive.close());

  // Favorites are keyed by song id and Hive lists a box by key: they listed
  // by id ('zz…' after 'aa…'), never newest first.
  test('newest liked first, whatever their ids', () async {
    await box.put('zz', HiveBoxes.favEntry(_song('zz'), 1000));
    await box.put('aa', HiveBoxes.favEntry(_song('aa'), 3000));
    await box.put('mm', HiveBoxes.favEntry(_song('mm'), 2000));
    expect(_ids(HiveBoxes.favoritesInOrder(box.values)), ['aa', 'mm', 'zz']);
  });

  test('a Rearrange sticks: the order given is the order kept', () async {
    await HiveBoxes.writeFavorites(box, [_song('zz'), _song('aa'), _song('mm')],
        now: DateTime(2026, 11, 1));
    expect(_ids(HiveBoxes.favoritesInOrder(box.values)), ['zz', 'aa', 'mm']);
    // Still under their ids, for the hearts.
    expect(box.containsKey('aa'), isTrue);
  });

  test('songs liked before Riff kept when come after, as they were', () async {
    await box.put('bb', _song('bb'));
    await box.put('aa', _song('aa'));
    await box.put('zz', HiveBoxes.favEntry(_song('zz'), 5000));
    expect(_ids(HiveBoxes.favoritesInOrder(box.values)), ['zz', 'aa', 'bb']);
  });
}
