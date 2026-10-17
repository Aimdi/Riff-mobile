import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/audio_handler.dart' show MediaLibrary;
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/saved_session.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Brings the saved session back as Riff's audio handler does: once, the
/// player told where it came from first, then the queue at its song and
/// place.
class _Handler extends BaseAudioHandler {
  late final comeback = SessionComeback(
      loaded: () => queue.value.isNotEmpty, bringBack: _bringBack);
  late PlayerController player;
  final asked = <Map<String, dynamic>?>[];
  Map<String, dynamic>? playByIndex;

  List<String> get ids => [for (final m in queue.value) m.id];

  Future<void> _bringBack(SavedSession session, {required bool play}) async {
    player.sessionCameBack(session.from);
    await updateQueue(session.queue);
    await customAction('playByIndex', {
      'index': session.index,
      'position': session.position.inMilliseconds,
      'restoreSession': !play,
    });
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    this.queue.add(List.of(queue));
    player.currentQueue.assignAll(queue);
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'restoreSession':
        asked.add(extras);
        return comeback(play: extras?['play'] == true);
      case 'playByIndex':
        playByIndex = extras;
        // As the player hears it from the handler.
        player.currentSong.value = queue.value[extras!['index'] as int];
        return true;
    }
    return null;
  }
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

MediaItem _episode(String id) => MediaItem(
    id: id,
    title: 'Episode $id',
    artist: 'A Show',
    extras: {'url': 'https://example.com/$id.mp3'});

final _sleep =
    PlaylingFrom(type: PlaylingFromType.PLAYLIST, name: 'Sleep', id: 'LIB1')
        .toJson();

/// What the player keeps when Riff goes to the background.
Future<void> _save(List<MediaItem> queue,
    {int index = 1, int position = 95000, Object? from}) async {
  final box = Hive.box('prevSessionData');
  await box.clear();
  await box.putAll({
    'queue': [for (final m in queue) MediaItemBuilder.toJson(m)],
    'index': index,
    'position': position,
    'from': from,
  });
}

/// Picking up where you left off, as Spotify, YouTube Music, Pocket Casts
/// and AntennaPod do: Riff opening, and Play pressed outside Riff (Android's
/// media controls once Riff was closed, headphones, the car, the
/// Assistant) with nothing loaded.
void main() {
  group('the saved session', () {
    setUp(() async {
      await Hive.openBox('prevSessionData', bytes: Uint8List(0));
    });
    tearDown(Hive.close);

    test('read back: its queue, song, place and where it came from',
        () async {
      final box = Hive.box('prevSessionData');
      expect(SavedSession.read(box), isNull);

      await _save([_song('a'), _episode('podcast_e'), _song('c')],
          from: _sleep);
      final saved = SavedSession.read(box)!;
      expect([for (final m in saved.queue) m.id], ['a', 'podcast_e', 'c']);
      expect(saved.song.id, 'podcast_e');
      expect(saved.song.extras?['url'], 'https://example.com/podcast_e.mp3');
      expect(saved.position, const Duration(seconds: 95));
      expect(PlaylingFrom.fromJson(saved.from).nameString, 'Sleep');

      // A place past the queue's end: its last song; none kept: the start.
      await box.putAll({'index': 7, 'position': null});
      expect(SavedSession.read(box)!.song.id, 'c');
      expect(SavedSession.read(box)!.position, Duration.zero);

      // Nothing that plays.
      await box.put('queue', const []);
      expect(SavedSession.read(box), isNull);
      await box.put('queue', 'garbled');
      expect(SavedSession.read(box), isNull);
    });

    test('comes back once, and not over something already playing',
        () async {
      await _save([_song('a'), _song('b')]);
      var loaded = false;
      final brought = <bool>[];
      final comeback = SessionComeback(
        loaded: () => loaded,
        bringBack: (session, {required play}) async {
          brought.add(play);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          loaded = true;
        },
      );

      // Riff opening and Play on the media controls at once: one comes
      // back, and the Play waits for it.
      final opening = comeback(play: false);
      expect(comeback.coming, isTrue);
      final pressed = comeback(play: true);
      expect(await opening, isTrue);
      expect(await pressed, isTrue);
      expect(brought, [false]);
      expect(comeback.coming, isFalse);

      // Something in the player: nothing comes back over it.
      expect(await comeback(play: true), isFalse);
      expect(brought, [false]);
    });

    test('nothing saved, or something else went in meanwhile: nothing back',
        () async {
      var loaded = false;
      final brought = <bool>[];
      final comeback = SessionComeback(
        loaded: () => loaded,
        bringBack: (session, {required play}) async => brought.add(play),
      );
      expect(await comeback(play: true), isFalse);

      // Android Auto starts a playlist while the session is read.
      await _save([_song('a')]);
      final asked = comeback(play: false);
      loaded = true;
      expect(await asked, isFalse);
      expect(brought, isEmpty);

      // Play with nothing loaded: it plays on from its place.
      loaded = false;
      expect(await comeback(play: true), isTrue);
      expect(brought, [true]);
    });
  });

  group('the player', () {
    late Directory tmp;
    late _Handler handler;
    late PlayerController player;

    setUp(() async {
      Get.reset();
      tmp = await Directory.systemTemp.createTemp('riff_left_off_');
      Hive.init(tmp.path);
      await Hive.openBox('AppPrefs');
      await Hive.openBox('prevSessionData');
      Get.put<MusicServices>(_FakeMusic());
      handler = Get.put<AudioHandler>(_Handler()) as _Handler;
      // Constructed directly: none of its listeners; Riff opening is its
      // onReady.
      player = PlayerController();
      handler.player = player;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    /// Riff's screens are up (the mini player is sized by them).
    Future<void> screens(WidgetTester tester) =>
        tester.pumpWidget(const GetMaterialApp(home: SizedBox()));

    /// Riff opening: the player, once its first screen is drawn.
    Future<void> open(WidgetTester tester) async {
      player.onReady();
      await tester.pump();
    }

    testWidgets(
        'Riff opens with what was playing, paused at its place, as Settings '
        'shows (on until switched off)', (tester) async {
      await screens(tester);
      await tester.runAsync(() =>
          _save([_song('a'), _episode('podcast_e'), _song('c')], from: _sleep));
      await open(tester);

      expect(handler.asked, [null]);
      expect(handler.ids, ['a', 'podcast_e', 'c']);
      expect(handler.playByIndex,
          {'index': 1, 'position': 95000, 'restoreSession': true});
      // It says where it came from, and the mini player shows it.
      expect(player.playinfrom.value.nameString, 'Sleep');
      expect(player.initFlagForPlayer, isFalse);
      expect(player.playerPanelMinHeight.value, greaterThan(0));
      expect(player.showContinueListening.value, isFalse);
    });

    testWidgets(
        'switched off: Riff opens with nothing loaded, and offers to '
        'continue', (tester) async {
      await screens(tester);
      await tester.runAsync(() async {
        await Hive.box('AppPrefs').put('restrorePlaybackSession', false);
        await _save([_song('a'), _song('b')]);
      });
      await open(tester);

      expect(handler.asked, isEmpty);
      expect(handler.ids, isEmpty);
      expect(player.initFlagForPlayer, isTrue);
      expect(player.showContinueListening.value, isTrue);
    });

    testWidgets(
        'brought back by Play outside Riff first: Riff opening shows it, '
        'and doesn\'t load it again', (tester) async {
      await tester.runAsync(() => _save([_song('a'), _song('b')]));
      // Android's media controls pressed Play before Riff's screens were up.
      expect(await handler.comeback(play: true), isTrue);
      expect(handler.playByIndex,
          {'index': 1, 'position': 95000, 'restoreSession': false});
      expect(player.initFlagForPlayer, isTrue);
      handler.playByIndex = null;

      await screens(tester);
      await open(tester);
      expect(handler.playByIndex, isNull);
      expect(handler.ids, ['a', 'b']);
      expect(player.initFlagForPlayer, isFalse);
      expect(player.showContinueListening.value, isFalse);
    });

    testWidgets(
        '"Play music on Riff" with nothing loaded: what was playing plays '
        'on from its place', (tester) async {
      await screens(tester);
      await tester
          .runAsync(() => _save([_episode('podcast_e'), _song('b')], index: 0));

      await player.playFromVoiceSearch(' ');
      expect(handler.ids, ['podcast_e', 'b']);
      expect(handler.playByIndex,
          {'index': 0, 'position': 95000, 'restoreSession': false});
    });

    testWidgets(
        'the media controls show the song of the session first; tapped, '
        'that session plays on', (tester) async {
      await screens(tester);
      final library = MediaLibrary();
      await tester.runAsync(() async {
        // Recently played keeps the oldest first.
        await (await Hive.openBox('LIBRP')).addAll([
          MediaItemBuilder.toJson(_song('old')),
          MediaItemBuilder.toJson(_song('a')),
        ]);
        // Nothing saved: the songs played lately, the newest first.
        var recent = await library.getByRootId(AudioService.recentRootId);
        expect([for (final m in recent) m.id], ['a', 'old']);

        await _save([_song('a'), _episode('podcast_e')]);
        recent = await library.getByRootId(AudioService.recentRootId);
        expect([for (final m in recent) m.id], ['podcast_e', 'a', 'old']);
        expect(recent.first.playable, isTrue);
        expect(recent.first.title, 'Episode podcast_e');
        expect(recent.first.extras?['libraryId'], MediaLibrary.lastSessionId);

        await player.playViaAndroidAuto(
            'podcast_e', MediaLibrary.lastSessionId);
        expect(handler.ids, ['a', 'podcast_e']);
        expect(handler.playByIndex,
            {'index': 1, 'position': 95000, 'restoreSession': false});
        expect(await Hive.boxExists(MediaLibrary.lastSessionId), isFalse);
      });
    });
  });
}
