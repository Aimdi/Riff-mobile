import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/song_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tmp;
  late Directory songs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_song_cache_');
    songs = Directory('${tmp.path}/cachedSongs')..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => tmp.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// A song as LockCachingAudioSource leaves it: the audio plus its
  /// content-type side file.
  void cache(String id) {
    File('${songs.path}/$id.mp3').writeAsBytesSync(List.filled(64, 1));
    File('${songs.path}/$id.mp3.mime').writeAsStringSync('audio/mp4');
  }

  List<String> files() =>
      songs.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('clearing cached songs removes their .mime files too', () async {
    cache('aaaaaaaaaaa');
    cache('bbbbbbbbbbb');

    final removed = await SongCacheService()
        .clearCachedSongs(protectedIds: {'bbbbbbbbbbb'});

    expect(removed, ['aaaaaaaaaaa']);
    // The playing / queued song keeps both files; the cleared one used to
    // leave `aaaaaaaaaaa.mp3.mime` behind for good.
    expect(files(), ['bbbbbbbbbbb.mp3', 'bbbbbbbbbbb.mp3.mime']);
  });

  test('eviction removes the .mime file with the song', () async {
    cache('ccccccccccc');

    final decision = await SongCacheService().evictIfNeeded(
      force: true,
      protectedIds: const {},
      maxBytes: 1,
    );

    expect(decision!.idsToDelete, ['ccccccccccc']);
    expect(files(), isEmpty);
  });
}
