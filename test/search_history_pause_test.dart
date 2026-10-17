import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/search_recents.dart';
import 'package:harmonymusic/ui/screens/Search/search_screen_controller.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _album = Album(
    title: 'Discovery',
    browseId: 'MPREb_1',
    artists: const [
      {'name': 'Daft Punk'}
    ],
    thumbnailUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox('searchQuery', bytes: Uint8List(0));
    SearchRecents.reload();
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
    SearchRecents.reload();
  });

  test('paused, what you open from search is not kept', () async {
    await SearchRecents.setPaused(true);
    await SearchRecents.note(_album);
    expect(SearchRecents.items, isEmpty);

    await SearchRecents.setPaused(false);
    await SearchRecents.note(_album);
    expect(SearchRecents.items.single.id, 'MPREb_1');
  });

  test('paused, what you search for is not kept', () async {
    Get.put<MusicServices>(_FakeMusic());
    final search = Get.put(SearchScreenController());
    await Future<void>.delayed(Duration.zero);

    await SearchRecents.setPaused(true);
    await search.addToHistryQueryList('daft punk');
    expect(search.historyQuerylist, isEmpty);
    expect(Hive.box('searchQuery').isEmpty, isTrue);

    await SearchRecents.setPaused(false);
    await search.addToHistryQueryList('daft punk');
    expect(search.historyQuerylist, ['daft punk']);
  });

  test('the switch is kept', () async {
    await SearchRecents.setPaused(true);
    SearchRecents.paused.value = false;
    SearchRecents.reload();
    expect(SearchRecents.paused.value, isTrue);
    expect(Hive.box('AppPrefs').get(SearchRecents.pausedKey), isTrue);
  });
}
