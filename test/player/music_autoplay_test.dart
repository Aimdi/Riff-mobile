import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_autoplay.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';

/// YouTube Music's radio: [tracks] for any song, or offline.
class _Music extends GetxService implements MusicServices {
  final asked = <String>[];
  bool offline = false;
  List<MediaItem> tracks = const [];

  @override
  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    asked.add(videoId);
    if (offline) throw NetworkError();
    return {'tracks': tracks, 'additionalParamsForNext': 'more'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Puts what the player queues in its queue (as the real handler's queue
/// stream does) and records the skips.
class _Handler extends BaseAudioHandler {
  late PlayerController player;
  final actions = <String>[];

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async =>
      player.currentQueue.addAll(mediaItems);

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    actions.add(name);
    return true;
  }
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Music music;
  late _Handler handler;
  late PlayerController player;

  setUp(() async {
    Get.reset();
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    music = Get.put<MusicServices>(_Music()) as _Music;
    handler = Get.put<AudioHandler>(_Handler()) as _Handler;
    // Constructed directly: no listeners, only the queue bookkeeping runs.
    player = PlayerController();
    handler.player = player;
    // An album's last song is playing.
    player.currentQueue.assignAll([_song('a1'), _song('a2')]);
    player.currentSongIndex.value = 1;
    player.currentSong.value = _song('a2');
  });
  tearDown(() async {
    await MusicAutoplay.set(false);
    Get.reset();
    await Hive.close();
  });

  test('off by default; kept when turned on', () async {
    expect(MusicAutoplay.enabled.value, isFalse);
    await MusicAutoplay.set(true);
    expect(Hive.box('AppPrefs').get(MusicAutoplay.key), isTrue);
  });

  test('the queue ran out: songs like its last one play on, as radio',
      () async {
    await MusicAutoplay.set(true);
    music.tracks = [_song('r1'), _song('a1'), _song('r2')];
    // Next works on the last song.
    expect(player.playsOnPastEnd, isTrue);

    expect(await player.autoplayAfterQueue(), isTrue);
    expect(music.asked, ['a2']);
    // Added after it (not what's already queued), then on to the next.
    expect(player.currentQueue.map((m) => m.id), ['a1', 'a2', 'r1', 'r2']);
    expect(handler.actions, ['skipToNext']);
    // From there it goes on as radio from that song does.
    expect(player.isRadioModeOn, isTrue);
    expect((player.radioInitiatorItem as MediaItem).id, 'a2');
    expect(player.playinfrom.value.name, 'autoplayShort');
  });

  test('off, after an episode or a book, or offline: the queue just ends',
      () async {
    expect(player.playsOnPastEnd, isFalse);
    expect(await player.autoplayAfterQueue(), isFalse);

    await MusicAutoplay.set(true);
    for (final item in const [
      MediaItem(id: 'podcast_1', title: 'Episode'),
      MediaItem(id: 'lv_42_3', title: 'Part 4'),
    ]) {
      player.currentSong.value = item;
      expect(player.playsOnPastEnd, isFalse);
      expect(await player.autoplayAfterQueue(), isFalse);
    }
    expect(music.asked, isEmpty);

    // Offline: nothing came; no error, and radio isn't left on.
    player.currentSong.value = _song('a2');
    music.offline = true;
    expect(await player.autoplayAfterQueue(), isFalse);
    expect(music.asked, ['a2']);
    expect(player.isRadioModeOn, isFalse);
    expect(player.radioInitiatorItem, isNull);
    expect(player.playbackError.value, isNull);
    expect(handler.actions, isEmpty);
  });

  test('radio already on goes on its own way', () async {
    await MusicAutoplay.set(true);
    player.isRadioModeOn = true;
    expect(player.playsOnPastEnd, isTrue);
    expect(await player.autoplayAfterQueue(), isFalse);
    expect(music.asked, isEmpty);
  });
}
