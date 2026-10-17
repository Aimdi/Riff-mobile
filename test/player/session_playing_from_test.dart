import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/taste_exclusions.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Keeps the queue as the audio handler does, and tells the player.
class _QueueHandler extends BaseAudioHandler {
  late PlayerController player;
  var items = <MediaItem>[];

  List<String> get ids => [for (final m in items) m.id];

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    items = List.of(queue);
    player.currentQueue.assignAll(items);
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'playByIndex') {
      player.currentSongIndex.value = extras!['index'] as int;
      return true;
    }
    return null;
  }
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

/// The session the audio handler saves when you leave the app.
Future<void> _saveSession(List<String> ids, {Map<String, String>? from}) async {
  final box = await Hive.openBox('prevSessionData');
  await box.clear();
  await box.putAll({
    'queue': [for (final id in ids) MediaItemBuilder.toJson(_song(id))],
    'index': 1,
    'position': 0,
    if (from != null) 'from': from,
  });
}

void main() {
  late Directory tmp;

  setUp(() async {
    Get.reset();
    tmp = await Directory.systemTemp.createTemp('riff_session_from_');
    Hive.init(tmp.path);
    await Hive.openBox('AppPrefs');
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('a resumed session still knows where it came from',
      (tester) async {
    // The player sizes its panel from the window (Get.size).
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
    Get.put<MusicServices>(_FakeMusic());
    final handler = Get.put<AudioHandler>(_QueueHandler()) as _QueueHandler;
    final player = PlayerController()..initFlagForPlayer = false;
    handler.player = player;

    await tester.runAsync(() async {
      // Your sleep playlist, left out of your taste profile, was playing.
      await TasteExclusions.setExcluded('LIB1', true);
      await _saveSession(['sleep00000a', 'sleep00000b'],
          from: PlaylingFrom(
                  type: PlaylingFromType.PLAYLIST, name: 'Sleep', id: 'LIB1')
              .toJson());

      expect(await player.resumeSavedSession(), isTrue);
    });
    expect(handler.ids, ['sleep00000a', 'sleep00000b']);
    final from = player.playinfrom.value;
    expect(from.type, PlaylingFromType.PLAYLIST);
    expect(from.nameString, 'Sleep');
    // The "Playing from" header opens it, and it stays out of your taste.
    expect(from.canOpen, isTrue);
    expect(TasteExclusions.excludesPlay(from), isTrue);

    // A session saved before Riff kept it: a selection, not what played
    // last.
    await tester.runAsync(() async {
      await _saveSession(['other00000a', 'other00000b']);
      expect(await player.resumeSavedSession(), isTrue);
    });
    expect(handler.ids, ['other00000a', 'other00000b']);
    expect(player.playinfrom.value.type, PlaylingFromType.SELECTION);
    expect(TasteExclusions.excludesPlay(player.playinfrom.value), isFalse);
  });
}
