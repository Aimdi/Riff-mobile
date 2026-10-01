// Drives the real app on an Android emulator: opens a YouTube Music podcast
// show the way a search result does, taps an episode and watches playback
// for a while. Run by the Device E2E workflow, which records logcat and
// screenshots alongside, so a crash on the device shows its native trace.
//
// The show can be changed with --dart-define=E2E_PODCAST="<search terms>".

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import 'package:harmonymusic/main.dart' as app;
import 'package:hive/hive.dart';

import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/free_audiobook_service.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

const _query = String.fromEnvironment('E2E_PODCAST',
    defaultValue: 'Handelsblatt Economic Challenges');

/// YouTube refuses stream urls to datacenter IPs, so on CI an episode never
/// starts. With this on, the episodes' entries in the app's own stream-url
/// cache point at a public LibriVox mp3: everything else (the real episode
/// items, queue, player, media session) runs exactly as on a phone where
/// YouTube answers.
const _stubStream = bool.fromEnvironment('E2E_STUB_STREAM', defaultValue: true);

Future<void> _cacheStreamUrl(List<MediaItem> episodes) async {
  final books = await FreeAudiobookService.popular(rows: 5);
  final detail = await FreeAudiobookService.detail(books.first.id);
  final chapter = detail!.chapters.reduce(
      (a, b) => a.durationSec >= b.durationSec ? a : b);
  final expire = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 6 * 3600;
  final url = '${chapter.url}?expire=$expire&riff_e2e=1';
  Map<String, dynamic> audio(int itag) => {
        'itag': itag,
        'audioCodec': 'Codec.mp4a',
        'bitrate': 64000,
        'loudnessDb': 0.0,
        'url': url,
        'approxDurationMs': chapter.durationSec * 1000,
        'size': 0,
      };
  final box = Hive.isBoxOpen('SongsUrlCache')
      ? Hive.box('SongsUrlCache')
      : await Hive.openBox('SongsUrlCache');
  for (final e in episodes.take(3)) {
    await box.put(e.id, {
      'playable': true,
      'statusMSG': 'OK',
      'lowQualityAudio': audio(139),
      'highQualityAudio': audio(140),
    });
  }
  _log('stream stub: ${chapter.durationSec}s LibriVox mp3 for '
      '${episodes.take(3).map((e) => e.id).join(', ')}: $url');
}

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
    if (_stubStream) {
      await tester.runAsync(() => _cacheStreamUrl(episodes));
    }

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
    Future<void> watch(String phase, int seconds) async {
      _log('--- $phase ($seconds s)');
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(seconds: 1));
        final p = pc.progressBarStatus.value;
        final state = 'song=${pc.currentSong.value?.id} '
            'button=${pc.buttonState.value} '
            'pos=${p.current.inSeconds ~/ 10 * 10}s/${p.total.inSeconds}s '
            'error=${pc.playbackError.value}';
        if (state != lastState) {
          _log(state);
          lastState = state;
        }
      }
    }

    Future<void> tapIcon(IconData icon, String label) async {
      final f = find.byIcon(icon);
      if (f.evaluate().isEmpty) {
        _log('no $label button on screen');
        return;
      }
      _log('tap $label');
      await tester.tap(f.first, warnIfMissed: false);
    }

    await watch('playing', 60);
    await tapIcon(Icons.forward_30_rounded, '+30s');
    await watch('after +30s', 15);
    await tapIcon(Icons.replay_10_rounded, '-10s');
    await watch('after -10s', 10);
    // Collapse the player to the mini player and back, as a user would.
    pc.playerPanelController.close();
    await watch('mini player', 10);
    pc.playerPanelController.open();
    await watch('player reopened', 10);
    await tapIcon(Icons.skip_next_rounded, 'next episode');
    await watch('next episode', 30);
    _log('done; ${errors.length} Flutter errors');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
