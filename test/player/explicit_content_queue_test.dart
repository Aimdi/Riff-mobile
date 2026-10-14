import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/explicit_content.dart';
import 'package:harmonymusic/services/music_autoplay.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';

/// YouTube Music's radio: [tracks] for any song.
class _Music extends GetxService implements MusicServices {
  final asked = <String>[];
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

MediaItem _song(String id, {bool explicit = false}) => MediaItem(
    id: id, title: 'Song $id', extras: {if (explicit) 'isExplicit': true});

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
    // An album whose last song is explicit; the one before it is playing.
    player.currentQueue
        .assignAll([_song('a1'), _song('a2'), _song('a3', explicit: true)]);
    player.currentSongIndex.value = 1;
    player.currentSong.value = _song('a2');
  });
  tearDown(() async {
    await MusicAutoplay.set(false);
    await ExplicitContent.set(true);
    Get.reset();
    await Hive.close();
  });

  test('allowed: a song after the one playing is next, as before', () async {
    await MusicAutoplay.set(true);
    music.tracks = [_song('r1')];
    expect(await player.autoplayAfterQueue(), isTrue);
    expect(music.asked, isEmpty);
    expect(handler.actions, ['skipToNext']);
  });

  test('off: an explicit last song is no song to play; Autoplay goes on',
      () async {
    await ExplicitContent.set(false);
    await MusicAutoplay.set(true);
    music.tracks = [_song('r1'), _song('r2')];
    expect(await player.autoplayAfterQueue(), isTrue);
    expect(music.asked, ['a2']);
    expect(
        player.currentQueue.map((m) => m.id), ['a1', 'a2', 'a3', 'r1', 'r2']);
    // The player skips the explicit one on its way to r1.
    expect(handler.actions, ['skipToNext']);
  });

  test(
      'offline: a last song that needs a connection is no song to play, nor '
      'are the ones Autoplay finds; downloaded, it plays next', () async {
    await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    await Hive.openBox('SongsCache', bytes: Uint8List(0));
    OfflinePlayback.offline.value = true;
    addTearDown(() => OfflinePlayback.offline.value = false);
    player.currentQueue.assignAll([_song('a1'), _song('a2'), _song('a3')]);
    await MusicAutoplay.set(true);
    music.tracks = [_song('r1')];
    expect(await player.autoplayAfterQueue(), isFalse);
    expect(music.asked, ['a2']);
    expect(handler.actions, isEmpty);

    await Hive.box('SongDownloads').put('a3', {'videoId': 'a3'});
    music.asked.clear();
    expect(await player.autoplayAfterQueue(), isTrue);
    expect(music.asked, isEmpty);
    expect(handler.actions, ['skipToNext']);
  });

  test(
      'turned off while an explicit song plays: on to the next; paused, it '
      'waits for Play', () async {
    player.currentSongIndex.value = 2;
    player.currentSong.value = _song('a3', explicit: true);
    player.buttonState.value = PlayButtonState.playing;
    await player.skipIfExplicit();
    expect(handler.actions, isEmpty);

    await ExplicitContent.set(false);
    player.buttonState.value = PlayButtonState.paused;
    await player.skipIfExplicit();
    expect(handler.actions, isEmpty);

    player.buttonState.value = PlayButtonState.playing;
    await player.skipIfExplicit();
    expect(handler.actions, ['skipToNext']);
  });
}
