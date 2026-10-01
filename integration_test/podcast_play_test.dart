// Drives the real app on an Android emulator: opens a YouTube Music podcast
// show the way a search result does, taps an episode and watches playback
// for a while. Run by the Device E2E workflow, which records logcat and
// screenshots alongside, so a crash on the device shows its native trace.
//
// The show can be changed with --dart-define=E2E_PODCAST="<search terms>".

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import 'package:harmonymusic/main.dart' as app;
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

const _query = String.fromEnvironment('E2E_PODCAST',
    defaultValue: 'Handelsblatt Economic Challenges');

void _log(String line) => debugPrint('E2E: $line');

/// Pumps frames in real time until [done] or [timeout].
Future<bool> _waitFor(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (done()) return true;
  }
  return done();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('play a YouTube Music podcast episode', (tester) async {
    // Errors are reported, not fatal: the point is to see how far playback
    // gets and what the device log says.
    final errors = <String>[];
    FlutterError.onError = (details) {
      errors.add(details.exceptionAsString());
      _log('FlutterError: ${details.exceptionAsString()}');
    };

    app.main();
    final ready = await _waitFor(
        tester,
        () =>
            Get.isRegistered<PlayerController>() &&
            Get.isRegistered<AudioHandler>(),
        timeout: const Duration(seconds: 60));
    _log('app ready: $ready');
    await _waitFor(tester, () => false, timeout: const Duration(seconds: 5));

    final ms = Get.find<MusicServices>();
    Playlist? show;
    List<MediaItem> episodes = const [];
    await tester.runAsync(() async {
      final res = await ms.search(_query, filter: 'podcasts', limit: 10);
      show = res.values
          .whereType<List>()
          .expand((l) => l)
          .whereType<Playlist>()
          .firstOrNull;
      if (show != null) {
        final pod = await ms.getPodcast(show!.playlistId, limit: 100);
        episodes = List<MediaItem>.from(pod['tracks'] as List);
      }
    });
    _log('show: ${show?.title} ${show?.playlistId}; '
        '${episodes.length} episodes');
    expect(show, isNotNull, reason: 'podcast search returned nothing');
    expect(episodes, isNotEmpty, reason: 'show has no episodes');
    final first = episodes.first;
    _log('first episode: ${first.id} "${first.title}" extras=${first.extras}');

    // Same route a tap on the search result takes.
    Get.toNamed(ScreenNavigationSetup.playlistScreen,
        id: ScreenNavigationSetup.id,
        arguments: [show, show!.playlistId, true]);
    final row = find.byKey(ValueKey(first.id));
    final listed = await _waitFor(tester, () => row.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45));
    _log('episode row shown: $listed');
    expect(listed, isTrue, reason: 'episode list did not load');

    _log('tapping episode ${first.id}');
    await tester.tap(row);

    final pc = Get.find<PlayerController>();
    String? lastState;
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(seconds: 1));
      final p = pc.progressBarStatus.value;
      final state = 'song=${pc.currentSong.value?.id} '
          'button=${pc.buttonState.value} '
          'pos=${p.current.inSeconds}s/${p.total.inSeconds}s '
          'error=${pc.playbackError.value}';
      if (state != lastState) {
        _log(state);
        lastState = state;
      }
    }
    _log('done; ${errors.length} Flutter errors');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
