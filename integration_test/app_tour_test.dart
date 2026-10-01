// A tour of the whole app on a device: every tab, search with each filter,
// an artist, album and playlist, a song in the player (controls, lyrics,
// queue, song sheet), a podcast episode, a free audiobook, Explore, Stats
// and Rewind. Every Flutter error is logged with the step it happened in
// and the app frames of its stack, so one run lists what is broken.
//
// Run by the Device E2E workflow with --dart-define=RIFF_E2E_STREAM_URL, so
// tracks play even though YouTube refuses stream urls to CI runners.

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import 'package:harmonymusic/main.dart' as app;
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/free_audiobook_service.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/free_audiobook_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';

void _log(String line) => debugPrint('TOUR: $line');

String _step = 'start';
final _errors = <String, List<String>>{};

void _record(String what, StackTrace? stack) {
  final frames = (stack?.toString() ?? '')
      .split('\n')
      .where((l) => l.contains('package:harmonymusic/'))
      .take(4)
      .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '').trim())
      .join(' <- ');
  final first = what.split('\n').first;
  final key = '$first @ $frames';
  _errors.putIfAbsent(key, () => []).add(_step);
  _log('ERROR in [$_step]: $first${frames.isEmpty ? '' : '\n      at $frames'}');
}

Future<void> _wait(WidgetTester tester, int seconds) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _step_(WidgetTester tester, String name,
    Future<void> Function() body, {int settle = 4}) async {
  _step = name;
  _log('--- $name');
  try {
    await body();
  } catch (e, st) {
    _record('step threw: $e', st);
  }
  await _wait(tester, settle);
}

Future<void> _tapIfShown(WidgetTester tester, Finder f, String label) async {
  if (f.evaluate().isEmpty) {
    _log('  ($label not on screen)');
    return;
  }
  _log('  tap $label');
  await tester.tap(f.first, warnIfMissed: false);
  await _wait(tester, 2);
}

Future<void> _scroll(WidgetTester tester) async {
  final s = find.byType(Scrollable);
  if (s.evaluate().isEmpty) return;
  await tester.fling(s.first, const Offset(0, -900), 2500,
      warnIfMissed: false);
  await _wait(tester, 2);
  await tester.fling(s.first, const Offset(0, 900), 2500,
      warnIfMissed: false);
}

void _go(String route, Object? args) => Get.toNamed(route,
    id: ScreenNavigationSetup.id, arguments: args, preventDuplicates: false);

void _back() => Get.back(id: ScreenNavigationSetup.id);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tour the app', (tester) async {
    FlutterError.onError = (d) => _record(d.exceptionAsString(), d.stack);

    app.main();
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(end) &&
        !(Get.isRegistered<PlayerController>() &&
            Get.isRegistered<AudioHandler>())) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await _wait(tester, 8);
    final home = Get.find<HomeScreenController>();
    final ms = Get.find<MusicServices>();
    final pc = Get.find<PlayerController>();

    await _step_(tester, 'home feed', () => _scroll(tester));

    const tabs = [
      'songs',
      'podcasts',
      'audiobooks',
      'playlists',
      'albums',
      'artists',
      'settings'
    ];
    for (var i = 0; i < tabs.length; i++) {
      await _step_(tester, 'tab ${tabs[i]}', () async {
        home.onSideBarTabSelected(i + 1);
        await _wait(tester, 4);
        await _scroll(tester);
      });
    }

    await _step_(tester, 'settings sections', () async {
      // Each settings card is an expandable section.
      for (final icon in [
        Icons.palette_outlined,
        Icons.tune,
        Icons.graphic_eq,
        Icons.info_outline,
      ]) {
        await _tapIfShown(tester, find.byIcon(icon), 'section $icon');
      }
      await _scroll(tester);
    });

    await _step_(tester, 'back to home', () async {
      home.onSideBarTabSelected(0);
    });

    // Search: the screen, then results with each filter pill.
    await _step_(tester, 'search screen',
        () async => _go(ScreenNavigationSetup.searchScreen, null));
    await _step_(tester, 'search results', () async {
      _go(ScreenNavigationSetup.searchResultScreen, 'coldplay');
      await _wait(tester, 8);
      for (final pill in [
        'Songs',
        'Videos',
        'Albums',
        'Artists',
        'Community playlists',
        'Featured playlists',
        'Podcasts',
        'Episodes',
      ]) {
        await _tapIfShown(tester, find.text(pill), 'filter $pill');
        await _wait(tester, 3);
      }
    }, settle: 2);
    _back();
    _back();

    // Artist, album and playlist pages from real search results.
    Artist? artist;
    Album? album;
    Playlist? playlist;
    await tester.runAsync(() async {
      try {
        final a = await ms.search('Coldplay', filter: 'artists', limit: 3);
        artist = a.values.whereType<List>().expand((l) => l).whereType<Artist>().firstOrNull;
        final b = await ms.search('Coldplay Parachutes', filter: 'albums', limit: 3);
        album = b.values.whereType<List>().expand((l) => l).whereType<Album>().firstOrNull;
        final p = await ms.search('chill hits', filter: 'community_playlists', limit: 3);
        playlist = p.values.whereType<List>().expand((l) => l).whereType<Playlist>().firstOrNull;
      } catch (e, st) {
        _record('search for pages: $e', st);
      }
    });
    _log('artist=${artist?.browseId} album=${album?.browseId} '
        'playlist=${playlist?.playlistId}');

    if (artist != null) {
      await _step_(tester, 'artist page', () async {
        _go(ScreenNavigationSetup.artistScreen, [true, artist!.browseId]);
        await _wait(tester, 10);
        await _scroll(tester);
      });
      _back();
    }
    if (album != null) {
      await _step_(tester, 'album page', () async {
        _go(ScreenNavigationSetup.albumScreen, (album, album!.browseId));
        await _wait(tester, 10);
        await _scroll(tester);
      });
    }

    // Play the album (or whatever the page shows) and use the player.
    await _step_(tester, 'play album', () async {
      await _tapIfShown(tester, find.byIcon(Icons.play_arrow_rounded), 'play');
      await _wait(tester, 10);
      _log('  now: ${pc.currentSong.value?.title} '
          'button=${pc.buttonState.value} error=${pc.playbackError.value}');
    }, settle: 2);
    if (album != null) _back();

    await _step_(tester, 'player controls', () async {
      pc.playerPanelController.open();
      await _wait(tester, 3);
      await _tapIfShown(tester, find.byIcon(Icons.shuffle_rounded), 'shuffle');
      await _tapIfShown(tester, find.byIcon(Icons.repeat_rounded), 'repeat');
      await _tapIfShown(tester, find.byIcon(Icons.skip_next_rounded), 'next');
      await _wait(tester, 6);
      await _tapIfShown(tester, find.byIcon(Icons.skip_previous_rounded), 'previous');
      await _wait(tester, 4);
      await _tapIfShown(tester, find.byIcon(Icons.lyrics_outlined), 'lyrics');
      await _wait(tester, 6);
      await _tapIfShown(tester, find.byIcon(Icons.lyrics), 'lyrics off');
      _log('  now: ${pc.currentSong.value?.title} '
          'button=${pc.buttonState.value} error=${pc.playbackError.value}');
    });
    await _step_(tester, 'song sheet', () async {
      await _tapIfShown(tester, find.byIcon(Icons.more_vert), 'menu');
      await _wait(tester, 3);
      await tester.tapAt(const Offset(20, 60));
    });
    await _step_(tester, 'queue', () async {
      pc.queuePanelController.open();
      await _wait(tester, 3);
      pc.queuePanelController.close();
    });
    await _step_(tester, 'mini player', () async {
      pc.playerPanelController.close();
    });

    if (playlist != null) {
      await _step_(tester, 'playlist page', () async {
        _go(ScreenNavigationSetup.playlistScreen,
            [playlist, playlist!.playlistId]);
        await _wait(tester, 10);
        await _scroll(tester);
      });
      _back();
    }

    // A YouTube Music podcast show and episode.
    await _step_(tester, 'podcast episode', () async {
      Playlist? show;
      await tester.runAsync(() async {
        final r = await ms.search('Handelsblatt Economic Challenges',
            filter: 'podcasts', limit: 5);
        show = r.values.whereType<List>().expand((l) => l).whereType<Playlist>().firstOrNull;
      });
      if (show == null) return;
      _go(ScreenNavigationSetup.playlistScreen, [show, show!.playlistId, true]);
      await _wait(tester, 10);
      await _tapIfShown(tester, find.text('Latest episode'), 'latest episode');
      await _wait(tester, 10);
      await _tapIfShown(tester, find.byIcon(Icons.forward_30_rounded), '+30');
      _log('  now: ${pc.currentSong.value?.title} '
          'button=${pc.buttonState.value} error=${pc.playbackError.value}');
      pc.playerPanelController.close();
      _back();
    });

    // A free LibriVox audiobook: detail page and its first chapter.
    await _step_(tester, 'free audiobook', () async {
      List<FreeAudiobook> books = const [];
      await tester.runAsync(() async {
        books = await FreeAudiobookService.popular(rows: 3);
      });
      if (books.isEmpty) return;
      Navigator.of(Get.nestedKey(ScreenNavigationSetup.id)!.currentContext!)
          .push(MaterialPageRoute(
              builder: (_) => FreeAudiobookScreen(book: books.first)));
      await _wait(tester, 10);
      await _scroll(tester);
      await _tapIfShown(tester, find.byIcon(Icons.play_arrow_rounded), 'play');
      await _wait(tester, 10);
      _log('  now: ${pc.currentSong.value?.title} '
          'button=${pc.buttonState.value} error=${pc.playbackError.value}');
      pc.playerPanelController.close();
      _back();
    });

    for (final r in [
      (ScreenNavigationSetup.exploreScreen, null),
      (ScreenNavigationSetup.statsScreen, null),
      (ScreenNavigationSetup.rewindScreen, null),
      (ScreenNavigationSetup.podcastsScreen, null),
      (ScreenNavigationSetup.pluginsScreen, null),
    ]) {
      await _step_(tester, 'route ${r.$1}', () async {
        _go(r.$1, r.$2);
        await _wait(tester, 6);
        await _scroll(tester);
      });
      _back();
    }

    await _step_(tester, 'recently played', () async {
      home.onSideBarTabSelected(0);
      await _wait(tester, 3);
      final pl = Playlist(
          title: 'Recently played',
          playlistId: 'LIBRP',
          thumbnailUrl: Playlist.thumbPlaceholderUrl,
          isCloudPlaylist: false);
      _go(ScreenNavigationSetup.playlistScreen, [pl, 'LIBRP']);
      await _wait(tester, 5);
      await _scroll(tester);
      _back();
    });

    _step = 'summary';
    _log('==== ${_errors.length} distinct errors');
    _errors.forEach((k, steps) =>
        _log('x${steps.length} [${steps.toSet().join(', ')}] $k'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
