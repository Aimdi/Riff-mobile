import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/long_track_resume.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/private_session.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the player's seeks.
class _Handler extends BaseAudioHandler {
  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}

const _hour = Duration(hours: 1);
const _min = Duration(minutes: 1);

MediaItem _track(String id, Duration length, {Map<String, dynamic>? extras}) =>
    MediaItem(id: id, title: id, duration: length, extras: extras);

/// Lets the Hive writes started without waiting finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  group('kept places', () {
    test('tracks of 20 minutes or more keep theirs', () {
      expect(LongTrackResume.keepsPlace(_min * 20), isTrue);
      expect(LongTrackResume.keepsPlace(_hour * 3), isTrue);
      expect(
          LongTrackResume.keepsPlace(const Duration(minutes: 19, seconds: 59)),
          isFalse);
      expect(LongTrackResume.keepsPlace(null), isFalse);
    });

    test('kept, and read back', () async {
      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 1);
      expect(LongTrackResume.placeOf('mix', _hour), _min * 12);
      expect(LongTrackResume.placeOf('other', _hour), Duration.zero);

      await LongTrackResume.save('mix', _min * 40, _hour, nowMs: 2);
      expect(LongTrackResume.placeOf('mix', _hour), _min * 40);
    });

    test('near its end or its start, it starts over', () async {
      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 1);
      await LongTrackResume.save(
          'mix', _min * 58 + const Duration(seconds: 1), _hour,
          nowMs: 2);
      expect(LongTrackResume.placeOf('mix', _hour), Duration.zero);

      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 3);
      await LongTrackResume.save('mix', const Duration(seconds: 59), _hour,
          nowMs: 4);
      expect(LongTrackResume.placeOf('mix', _hour), Duration.zero);
    });

    test('songs keep none', () async {
      await LongTrackResume.save('song', _min * 2, _min * 4, nowMs: 1);
      expect(Hive.box('AppPrefs').get(LongTrackResume.key), isNull);
      expect(LongTrackResume.placeOf('song', _min * 4), Duration.zero);
    });

    test('read before its length is known', () async {
      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 1);
      expect(LongTrackResume.placeOf('mix', null), _min * 12);
      expect(LongTrackResume.placeOf('mix', Duration.zero), _min * 12);
      // Known, and short: none.
      expect(LongTrackResume.placeOf('mix', _min * 10), Duration.zero);
    });

    test('the 50 kept last are kept', () async {
      for (var i = 0; i < LongTrackResume.max + 2; i++) {
        await LongTrackResume.save('t$i', _min * 5, _hour, nowMs: i);
      }
      final kept = Hive.box('AppPrefs').get(LongTrackResume.key) as Map;
      expect(kept.length, LongTrackResume.max);
      expect(LongTrackResume.placeOf('t0', _hour), Duration.zero);
      expect(LongTrackResume.placeOf('t1', _hour), Duration.zero);
      expect(LongTrackResume.placeOf('t2', _hour), _min * 5);
      expect(LongTrackResume.placeOf('t51', _hour), _min * 5);
    });

    test('forgotten (Start over)', () async {
      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 1);
      await LongTrackResume.forget('mix');
      expect(LongTrackResume.placeOf('mix', _hour), Duration.zero);
    });

    test('its time', () {
      expect(longTrackPlaceLabel(const Duration(minutes: 23, seconds: 45)),
          '23:45');
      expect(
          longTrackPlaceLabel(const Duration(minutes: 5, seconds: 7)), '5:07');
      expect(
          longTrackPlaceLabel(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
  });

  group('the player', () {
    late PlayerController player;
    late _Handler handler;

    setUp(() {
      Get.put<MusicServices>(_FakeMusic());
      player = Get.put(PlayerController());
      handler = _Handler();
    });
    tearDown(() async {
      Get.delete<PlayerController>();
      // End the controller's wait for the audio handler.
      Get.put<AudioHandler>(_Handler());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    /// Runs [body] with [handler] there, all at once: the player's own
    /// start, which would find it at its next look, needs AudioService.
    void withHandler(void Function() body) {
      Get.put<AudioHandler>(handler);
      try {
        body();
      } finally {
        Get.delete<AudioHandler>();
      }
    }

    /// [item] starts playing, [total] long.
    void start(MediaItem item, {Duration? total}) {
      player.armStart(item);
      player.currentSong.value = item;
      player.progressBarStatus.update((s) {
        s!.current = Duration.zero;
        s.total = total ?? item.duration!;
      });
    }

    test('a long track plays on from its place', () async {
      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 1);
      withHandler(() {
        start(_track('mix', _hour));
        player.onPlaybackPosition(Duration.zero);
        // Once.
        player.onPlaybackPosition(const Duration(seconds: 1));
      });
      expect(handler.seeks, [_min * 12]);
    });

    test('a song, or a long track with no place, plays from the start',
        () async {
      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 1);
      withHandler(() {
        start(_track('song', _min * 4));
        player.onPlaybackPosition(Duration.zero);
        start(_track('set', _hour * 2));
        player.onPlaybackPosition(Duration.zero);
      });
      expect(handler.seeks, isEmpty);
    });

    test('Start over: from the start, its place forgotten', () async {
      await LongTrackResume.save('mix', _min * 12, _hour, nowMs: 1);
      withHandler(() {
        start(_track('mix', _hour));
        player.onPlaybackPosition(Duration.zero);
        player.startLongTrackOver('mix');
      });
      expect(handler.seeks, [_min * 12, Duration.zero]);
      await _settle();
      expect(LongTrackResume.placeOf('mix', _hour), Duration.zero);
    });

    test('its place is kept as it plays, every few seconds', () async {
      final mix = _track('mix', _hour);
      player.currentSong.value = mix;
      player.progressBarStatus.update((s) => s!.total = _hour);
      player.onPlaybackPosition(_min * 30);
      await _settle();
      expect(LongTrackResume.placeOf('mix', _hour), _min * 30);

      player.onPlaybackPosition(_min * 31);
      await _settle();
      expect(LongTrackResume.placeOf('mix', _hour), _min * 30);
    });

    test('nor in a private session, nor for audiobooks', () async {
      await PrivateSession.start();
      player.currentSong.value = _track('mix', _hour);
      player.progressBarStatus.update((s) => s!.total = _hour);
      player.onPlaybackPosition(_min * 30);
      await _settle();
      expect(LongTrackResume.placeOf('mix', _hour), Duration.zero);
      await PrivateSession.stop();

      player.currentSong.value =
          _track('lv_book_1', _hour, extras: {'streamSource': 'librivox'});
      player.onPlaybackPosition(_min * 30);
      await _settle();
      expect(Hive.box('AppPrefs').get(LongTrackResume.key), isNull);
    });

    test("a free audiobook's chapter plays on from where it was left",
        () async {
      final chapter =
          _track('lv_book_2', _min * 30, extras: {'streamSource': 'librivox'});
      withHandler(() {
        // As the book's page (or Jump back in) plays it.
        player.armResume('lv_book_2', (_min * 10).inMilliseconds);
        start(chapter);
        player.onPlaybackPosition(Duration.zero);
      });
      expect(handler.seeks, [_min * 10]);
    });
  });

  testWidgets('says where it picked up, with Start over', (tester) async {
    await tester.runAsync(() => LongTrackResume.save(
        'mix', const Duration(minutes: 12, seconds: 5), _hour,
        nowMs: 1));
    Get.put<MusicServices>(_FakeMusic());
    final player = Get.put(PlayerController());
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      locale: const Locale('en', 'US'),
      translationsKeys: const {
        'en_US': {
          'longTrackResumed': 'Picked up at @time',
          'startOver': 'Start over',
        },
      },
      home: const Scaffold(body: SizedBox.expand()),
    ));

    final mix = _track('mix', _hour);
    player.armStart(mix);
    player.currentSong.value = mix;
    player.progressBarStatus.update((s) => s!.total = _hour);
    player.onPlaybackPosition(Duration.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Picked up at 12:05'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Start over'));
      await _settle();
    });
    expect(LongTrackResume.placeOf('mix', _hour), Duration.zero);

    // End the controller's wait for the audio handler.
    Get.delete<PlayerController>();
    Get.put<AudioHandler>(_Handler());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
