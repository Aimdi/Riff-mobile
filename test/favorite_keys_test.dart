import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/hive_boxes.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    Hive.init('.');
    await Hive.openBox(HiveBoxes.libFav, bytes: Uint8List(0));
  });
  tearDown(() async => Hive.close());

  test('Favorites kept by position are put back under song ids', () async {
    final box = Hive.box(HiveBoxes.libFav);
    await box.putAll({
      0: {'videoId': 'songAAAAAAA', 'title': 'A'},
      1: {'videoId': 'songBBBBBBB', 'title': 'B'},
    });
    expect(HiveBoxes.favContains('songAAAAAAA'), isFalse);

    await HiveBoxes.fav();
    expect(box.keys, unorderedEquals(['songAAAAAAA', 'songBBBBBBB']));
    expect(HiveBoxes.favContains('songAAAAAAA'), isTrue);
    expect(box.get('songBBBBBBB')['title'], 'B');
  });

  test('Favorites already by song id are left alone', () async {
    final box = Hive.box(HiveBoxes.libFav);
    await box.put('songAAAAAAA', {'videoId': 'songAAAAAAA'});
    await HiveBoxes.fav();
    expect(box.keys, ['songAAAAAAA']);
  });
}
