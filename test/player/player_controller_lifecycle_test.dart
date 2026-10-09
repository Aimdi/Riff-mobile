import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/smart_queue_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandler extends BaseAudioHandler {}

/// Listeners currently registered on a GetX observable.
int _listeners(RxInterface rx) => (rx as dynamic).subject.length as int;

/// Lets the controller's wait-for-AudioHandler poll (every 50 ms) run.
Future<void> _letPollRun() =>
    Future<void>.delayed(const Duration(milliseconds: 200));

void main() {
  // Plain `test`s: the binding exists (GetX schedules onReady on it) but no
  // frame is pumped, so only onInit / onClose run.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.reset();
    Get.put<MusicServices>(_FakeMusic());
  });
  tearDown(Get.reset);

  test('closing the player releases its workers, timer and smart queue',
      () async {
    final segments = _listeners(PodcastSegmentStore.rev);
    final prefs = _listeners(PodcastPlaybackPrefs.rev);
    final smartQueue = Get.put(SmartQueueService());

    final player = Get.put(PlayerController());
    smartQueue.attach(player);
    // App-wide observables: these workers kept a deleted controller
    // reachable (and rebuilding segments) for the rest of the process.
    expect(_listeners(PodcastSegmentStore.rev), segments + 1);
    expect(_listeners(PodcastPlaybackPrefs.rev), prefs + 1);
    expect(_listeners(player.currentSong), 1);
    expect(player.startSleepTimer(5), isTrue);

    // GetX calls onClose on delete; the old cleanup lived in dispose(),
    // which GetX never calls.
    Get.delete<PlayerController>();

    expect(_listeners(PodcastSegmentStore.rev), segments);
    expect(_listeners(PodcastPlaybackPrefs.rev), prefs);
    expect(_listeners(player.currentSong), 0);
    expect(player.sleepTimer!.isActive, isFalse);

    // End the controller's handler poll.
    Get.put<AudioHandler>(_FakeHandler());
    await _letPollRun();
  });

  test('a player closed while waiting for the audio handler never listens',
      () async {
    Get.put(PlayerController());
    Get.delete<PlayerController>();

    // The handler finishes starting only after the controller is gone.
    final handler = _FakeHandler();
    Get.put<AudioHandler>(handler);
    await _letPollRun();

    expect(handler.playbackState.hasListener, isFalse);
    expect(handler.mediaItem.hasListener, isFalse);
    expect(handler.queue.hasListener, isFalse);
  });
}
