import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/audio_handler.dart' show MediaLibrary;
import 'package:harmonymusic/services/music_service.dart';
import 'package:hive/hive.dart';

MediaItem _song(String id) => MediaItem(
    id: id,
    title: 'Song $id',
    artist: 'Artist',
    artUri: Uri.parse('https://lh3.googleusercontent.com/$id'));

class _FakeMusic extends GetxService implements MusicServices {
  String? asked;
  Object? failure;
  List<MediaItem> songs = const [];

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    asked = '$query|$filter';
    if (failure != null) throw failure!;
    return {'Songs': songs};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await Hive.openBox('LIBFAV', bytes: Uint8List(0));
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  test('the car searches songs, best match first, played from that list',
      () async {
    final music =
        Get.put<MusicServices>(_FakeMusic()..songs = [_song('s1'), _song('s2')])
            as _FakeMusic;
    final found = await MediaLibrary().searchSongs('  daft punk ');
    expect(music.asked, 'daft punk|songs');
    expect(found.map((m) => m.id), ['s1', 's2']);
    expect(found.every((m) => m.playable == true), isTrue);
    expect(found.first.extras?['libraryId'], MediaLibrary.searchResultsId);
    // Played from the list the car found, as its other lists are.
    expect(MediaLibrary.isBuiltList(MediaLibrary.searchResultsId), isTrue);
    expect(MediaLibrary.listIdFor('s2'), MediaLibrary.searchResultsId);
    expect(
        MediaLibrary.autoPodcastLists[MediaLibrary.searchResultsId]!
            .map((m) => m.id),
        ['s1', 's2']);
  });

  test('nothing asked for, or no connection: nothing found', () async {
    final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
    expect(await MediaLibrary().searchSongs('   '), isEmpty);
    expect(music.asked, isNull);
    music.failure = Exception('offline');
    expect(await MediaLibrary().searchSongs('anything'), isEmpty);
  });

  test('"play … on Riff" plays what the search finds', () async {
    Get.put<MusicServices>(_FakeMusic()..songs = [_song('hit')]);
    expect((await MediaLibrary().voiceSearchList('a hit')).map((m) => m.id),
        ['hit']);
  });

  test('"play music on Riff": your Favorites, shuffled', () async {
    final favorites = Hive.box('LIBFAV');
    for (final id in ['f1', 'f2', 'f3']) {
      await favorites.put(id, MediaItemBuilder.toJson(_song(id)));
    }
    final list = await MediaLibrary().voiceSearchList(' ', random: Random(7));
    expect(list.map((m) => m.id).toSet(), {'f1', 'f2', 'f3'});
  });
}
