import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/screens/Search/search_screen_controller.dart';
import 'package:hive/hive.dart';

import '../fakes/fake_music_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FakeMusicServices music;
  late SearchScreenController c;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('search_ctrl');
    Hive.init(tmp.path);
    music = FakeMusicServices();
    Get.put<MusicServices>(music);
    c = Get.put(SearchScreenController());
    // onInit opens the history box asynchronously.
    await Hive.openBox('searchQuery');
    await pumpEventQueue();
  });

  tearDown(() async {
    Get.reset();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  test('a failed suggestion request is not an uncaught error', () async {
    music.error = Exception('offline');
    // Was: the exception escaped (from the debounce timer when typing).
    await c.suggestionInput('radio');
    expect(music.suggestionCalls, ['radio']);
    expect(c.suggestionList, isEmpty);

    music.error = null;
    await c.suggestionInput('radio');
    expect(c.suggestionList, ['radio suggestion']);
  });

  test('searching a query already in a full history keeps all ten', () async {
    for (var i = 0; i < 10; i++) {
      await c.addToHistryQueryList('q$i');
    }
    expect(c.historyQuerylist, hasLength(10));

    // Already there: nothing to make room for (used to drop q0).
    await c.addToHistryQueryList('q5');
    expect(c.historyQuerylist, hasLength(10));
    expect(c.historyQuerylist, contains('q0'));
    expect(c.queryBox.length, 10);

    // A new one still evicts the oldest.
    await c.addToHistryQueryList('new');
    expect(c.historyQuerylist, hasLength(10));
    expect(c.historyQuerylist.first, 'new');
    expect(c.historyQuerylist, isNot(contains('q0')));
    expect(c.queryBox.values, isNot(contains('q0')));
  });

  test('removing a query that is not stored does not throw', () async {
    await c.addToHistryQueryList('kept');
    c.historyQuerylist.add('ghost');
    await c.removeQueryFromHistory('ghost');
    expect(c.historyQuerylist, ['kept']);
    expect(c.queryBox.values, ['kept']);
  });
}
