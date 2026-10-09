import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

/// YouTube Music while offline: every request fails like `_sendRequest`
/// does when its retries run out.
class _OfflineMusic extends GetxService implements MusicServices {
  int watchPlaylistCalls = 0;

  @override
  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    watchPlaylistCalls++;
    throw NetworkError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _OfflineMusic music;

  setUp(() {
    Get.reset();
    music = Get.put<MusicServices>(_OfflineMusic()) as _OfflineMusic;
  });
  tearDown(Get.reset);

  test(
      'radio reaching the end offline reports radioContinuationFailed '
      'instead of throwing', () async {
    // Constructed directly: no AudioHandler, no lifecycle — only the radio
    // bookkeeping runs.
    final player = PlayerController()
      ..isRadioModeOn = true
      ..radioInitiatorItem = _song('seed');
    player.currentQueue.assignAll([_song('seed')]);
    player.currentSongIndex.value = 0;

    // Used to rethrow the NetworkError out of the end-of-track skip, so the
    // error never showed and the notification's skip failed.
    final advanced = await player.extendRadioThenPlayNext();

    expect(advanced, isFalse);
    expect(music.watchPlaylistCalls, 1);
    expect(player.playbackError.value, 'radioContinuationFailed');

    // The in-flight guard was released: a later attempt fetches again.
    expect(await player.extendRadioThenPlayNext(), isFalse);
    expect(music.watchPlaylistCalls, 2);
  });
}
