import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/song_list_tile.dart';
import 'package:hive/hive.dart';

MediaItem _song(String id, {Map<String, dynamic>? extras}) =>
    MediaItem(id: id, title: 'Song $id', artist: 'Artist', extras: extras);

class _FakePlayer extends GetxController implements PlayerController {
  /// Times a row said it can't play offline.
  int offlineSaid = 0;

  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isCurrentSongFav = false.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  void notifyOffline() => offlineSaid++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = true.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The dimmed row of a song that won't play.
final _dimmed = find.byWidgetPredicate(
    (w) => w is Opacity && w.opacity == RiffPalette.unavailableOpacity);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    await Hive.openBox('SongsCache', bytes: Uint8List(0));
    await Hive.box('SongDownloads').put('saved', {'videoId': 'saved'});
    await Hive.box('SongsCache').put('cached', {'videoId': 'cached'});
  });
  tearDown(() async {
    await OfflinePlayback.resetForTest();
    messenger.setMockStreamHandler(OfflinePlayback.channel, null);
    debugDefaultTargetPlatformOverride = null;
    await Hive.close();
  });

  test(
      'songs that need a connection: YouTube songs neither downloaded nor '
      'cached', () {
    expect(OfflinePlayback.needsConnection(_song('online')), isTrue);
    expect(OfflinePlayback.needsConnection(_song('saved')), isFalse);
    expect(OfflinePlayback.needsConnection(_song('cached')), isFalse);
    // Episodes, books and songs from elsewhere go as before.
    for (final id in [
      'podcast_1',
      'abs_1',
      'lv_1',
      'cloud_1',
      'slsk_1',
    ]) {
      expect(OfflinePlayback.needsConnection(_song(id)), isFalse, reason: id);
    }
    expect(
        OfflinePlayback.needsConnection(
            _song('yt_episode', extras: {'isPodcast': true})),
        isFalse);
    expect(
        OfflinePlayback.needsConnection(
            _song('server', extras: {'streamSource': 'cloud'})),
        isFalse);
  });

  test("online, or can't tell: nothing is passed over", () async {
    expect(OfflinePlayback.blocks(_song('online')), isFalse);
    OfflinePlayback.offline.value = true;
    expect(OfflinePlayback.blocks(_song('online')), isTrue);
    expect(OfflinePlayback.blocks(_song('saved')), isFalse);
    expect(OfflinePlayback.blocks(null), isFalse);
    // The download boxes not open: as if kept.
    await Hive.close();
    expect(OfflinePlayback.blocks(_song('online')), isFalse);
  });

  test('follows what the phone says, from when it starts listening', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    late MockStreamHandlerEventSink phone;
    messenger.setMockStreamHandler(OfflinePlayback.channel,
        MockStreamHandler.inline(onListen: (_, events) {
      phone = events;
      events.success(false);
    }));
    OfflinePlayback.watch();
    await pumpEventQueue();
    expect(OfflinePlayback.offline.value, isTrue);

    phone.success(true);
    await pumpEventQueue();
    expect(OfflinePlayback.offline.value, isFalse);

    phone.success(false);
    await pumpEventQueue();
    expect(OfflinePlayback.offline.value, isTrue);
    // Can't tell any more: online.
    phone.error(code: 'gone');
    await pumpEventQueue();
    expect(OfflinePlayback.offline.value, isFalse);
  });

  test('off Android it never listens: always online', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var listened = false;
    messenger.setMockStreamHandler(OfflinePlayback.channel,
        MockStreamHandler.inline(onListen: (_, events) {
      listened = true;
      events.success(false);
    }));
    OfflinePlayback.watch();
    await pumpEventQueue();
    expect(listened, isFalse);
    expect(OfflinePlayback.offline.value, isFalse);
  });

  test('Offline mode: as with no connection, kept across restarts', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    expect(OfflinePlayback.blocks(_song('online')), isFalse);

    await OfflinePlayback.setMode(true);
    expect(OfflinePlayback.offline.value, isTrue);
    expect(OfflinePlayback.byChoice, isTrue);
    expect(OfflinePlayback.blocks(_song('online')), isTrue);
    expect(OfflinePlayback.blocks(_song('saved')), isFalse);
    expect(Hive.box('AppPrefs').get(OfflinePlayback.modeKey), isTrue);

    // The next start: on as it was left.
    OfflinePlayback.mode.value = false;
    OfflinePlayback.offline.value = false;
    OfflinePlayback.watch();
    expect(OfflinePlayback.mode.value, isTrue);
    expect(OfflinePlayback.offline.value, isTrue);

    await OfflinePlayback.setMode(false);
    expect(OfflinePlayback.offline.value, isFalse);
    expect(Hive.box('AppPrefs').get(OfflinePlayback.modeKey), isFalse);
  });

  test('Offline mode and the connection together', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    late MockStreamHandlerEventSink phone;
    messenger.setMockStreamHandler(OfflinePlayback.channel,
        MockStreamHandler.inline(onListen: (_, events) {
      phone = events;
      events.success(true);
    }));
    OfflinePlayback.watch();
    await pumpEventQueue();
    expect(OfflinePlayback.offline.value, isFalse);

    await OfflinePlayback.setMode(true);
    expect(OfflinePlayback.offline.value, isTrue);
    expect(OfflinePlayback.byChoice, isTrue);

    // No connection either: it says so, not that Offline mode is on.
    phone.success(false);
    await pumpEventQueue();
    expect(OfflinePlayback.byChoice, isFalse);

    // Offline mode off, still no connection: offline all the same.
    await OfflinePlayback.setMode(false);
    expect(OfflinePlayback.offline.value, isTrue);
    phone.success(true);
    await pumpEventQueue();
    expect(OfflinePlayback.offline.value, isFalse);
  });

  group('song rows', () {
    late _FakePlayer player;

    setUp(() {
      player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
      Get.put<SettingsScreenController>(_FakeSettings());
    });
    tearDown(Get.reset);

    Future<void> pumpRow(
            WidgetTester tester, MediaItem song, VoidCallback onTap) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(
            body: SongListTile(
                song: song,
                onTap: onTap,
                thumbReplacementWithIndex: true,
                index: 1),
          ),
        ));

    testWidgets(
        'offline, a song that needs a connection is dimmed and a tap says '
        'why; back online, it plays', (tester) async {
      var played = 0;
      await pumpRow(tester, _song('online'), () => played++);
      expect(_dimmed, findsNothing);

      OfflinePlayback.offline.value = true;
      await tester.pump();
      expect(_dimmed, findsOneWidget);
      await tester.tap(find.text('Artist'));
      expect(played, 0);
      expect(player.offlineSaid, 1);

      OfflinePlayback.offline.value = false;
      await tester.pump();
      expect(_dimmed, findsNothing);
      await tester.tap(find.text('Artist'));
      expect(played, 1);
    });

    testWidgets('a downloaded song plays offline as ever', (tester) async {
      OfflinePlayback.offline.value = true;
      var played = 0;
      await pumpRow(tester, _song('saved'), () => played++);
      expect(_dimmed, findsNothing);
      await tester.tap(find.text('Artist'));
      expect(played, 1);
      expect(player.offlineSaid, 0);
    });
  });
}
