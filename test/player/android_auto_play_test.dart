import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:harmonymusic/services/audio_handler.dart' show MediaLibrary;
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what the player hands the audio handler.
class _RecordingHandler extends BaseAudioHandler {
  List<String>? queuedIds;
  Map<String, dynamic>? playByIndex;

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    queuedIds = queue.map((m) => m.id).toList();
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'playByIndex') playByIndex = extras;
    return true;
  }
}

Map<String, dynamic> _track(String id) => {'videoId': id, 'title': 'T $id'};

void main() {
  late Directory tmp;

  setUp(() async {
    Get.reset();
    tmp = await Directory.systemTemp.createTemp('riff_aa_play_');
    Hive.init(tmp.path);
    await Hive.openBox('AppPrefs');
    final mixes = await Hive.openBox('riff_mixes');
    await mixes.put('m1', {
      'id': 'm1',
      'kind': 'daily_mix',
      'title': 'Daily Mix 1',
      'tracks': [_track('t1'), _track('t2'), _track('t3')],
    });
    await mixes.put('f1', {
      'id': 'f1',
      'kind': 'fresh_finds',
      'title': 'Fresh finds',
      'tracks': [_track('f1a'), _track('f1b')],
    });
    final fav = await Hive.openBox('LIBFAV');
    await fav.put('a', _track('a'));
    await fav.put('b', _track('b'));
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('Android Auto plays a track with the list it was browsed in',
      (tester) async {
    // playPlayListSong sizes the panel from the window (Get.size).
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
    Get.put<MusicServices>(_FakeMusic());
    final handler =
        Get.put<AudioHandler>(_RecordingHandler()) as _RecordingHandler;
    // Constructed directly: no listeners, only the play path runs.
    final player = PlayerController()..initFlagForPlayer = false;

    await tester.runAsync(() async {
      // A Daily Mix track: the list id the car reports is the mix's.
      await player.playViaAndroidAuto('t2', 'riff_mix_m1');
      expect(handler.queuedIds, ['t1', 't2', 't3']);
      expect(handler.playByIndex, {'index': 1});
      // It used to open "riff_mix_m1" as a Hive box: a new empty box file
      // for every mix, an empty queue, and nothing played.
      expect(await Hive.boxExists('riff_mix_m1'), isFalse);

      await player.playViaAndroidAuto('f1b', MediaLibrary.freshFindsRootId);
      expect(handler.queuedIds, ['f1a', 'f1b']);
      expect(handler.playByIndex, {'index': 1});
      expect(await Hive.boxExists(MediaLibrary.freshFindsRootId), isFalse);

      // Library lists still play from their own box.
      await player.playViaAndroidAuto('b', 'LIBFAV');
      expect(handler.queuedIds, ['a', 'b']);
      expect(handler.playByIndex, {'index': 1});

      // Let playPlayListSong's delayed Home refresh check run while the
      // prefs box is still open.
      await Future<void>.delayed(const Duration(milliseconds: 3200));
    });
  });

  test('only car-built lists skip the box lookup', () {
    expect(MediaLibrary.isBuiltList('riff_mix_m1'), isTrue);
    expect(MediaLibrary.isBuiltList(MediaLibrary.freshFindsRootId), isTrue);
    expect(MediaLibrary.isBuiltList(MediaLibrary.podcastProgressId), isTrue);
    expect(
        MediaLibrary.isBuiltList('${MediaLibrary.podcastFeedPrefix}x'), isTrue);
    expect(MediaLibrary.isBuiltList('LIBFAV'), isFalse);
    expect(MediaLibrary.isBuiltList('SongDownloads'), isFalse);
    expect(MediaLibrary.isBuiltList('PLsomeplaylist'), isFalse);
  });
}
