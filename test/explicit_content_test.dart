import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/explicit_content.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/song_list_tile.dart';
import 'package:hive/hive.dart';

const _explicit = MediaItem(
    id: 'e', title: 'Song E', artist: 'Artist', extras: {'isExplicit': true});
const _clean = MediaItem(id: 'c', title: 'Song C', artist: 'Artist');

class _FakePlayer extends GetxController implements PlayerController {
  /// Times a row said why its song won't play.
  int explained = 0;

  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isCurrentSongFav = false.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  void notifyExplicitOff() => explained++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = true.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Next's order through a queue of [length]: the last stays put, or with
/// [repeat] the first comes round again.
int Function(int) _next(int length, {bool repeat = false}) =>
    (at) => at + 1 < length
        ? at + 1
        : repeat
            ? 0
            : at;

/// The dimmed row of a song that won't play.
final _dimmed = find.byWidgetPredicate(
    (w) => w is Opacity && w.opacity == RiffPalette.unavailableOpacity);

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
  });
  tearDown(() async {
    await ExplicitContent.set(true);
    await Hive.close();
  });

  test('allowed by default: nothing is blocked or left out', () {
    expect(ExplicitContent.allowed.value, isTrue);
    expect(ExplicitContent.blocks(_explicit), isFalse);
    final tracks = [_clean, _explicit];
    expect(ExplicitContent.filter(tracks), same(tracks));
  });

  test(
      'turned off: explicit songs are blocked and left out, but not the one '
      'asked for', () async {
    await ExplicitContent.set(false);
    expect(Hive.box('AppPrefs').get(ExplicitContent.key), isFalse);
    expect(ExplicitContent.blocks(_explicit), isTrue);
    expect(ExplicitContent.blocks(_clean), isFalse);
    expect(ExplicitContent.blocks(null), isFalse);
    expect(ExplicitContent.filter([_clean, _explicit]).map((s) => s.id), ['c']);
    expect(
        ExplicitContent.filter([_explicit, _clean], keepId: 'e')
            .map((s) => s.id),
        ['e', 'c']);
    // Raw track maps too.
    expect(
        ExplicitContent.filter([
          {'videoId': 'x', 'isExplicit': true},
          {'videoId': 'y'},
        ]).map((t) => t['videoId']),
        ['y']);
  });

  group('where play goes from an explicit song', () {
    // a, E, c, E, E: only the first and the third may play.
    bool mayPlay(int i) => i == 0 || i == 2;

    test('on to the next song that may play', () {
      expect(playableFrom(1, 5, step: _next(5), mayPlay: mayPlay).index, 2);
    });

    test('going back, to the one before it', () {
      final back = playableFrom(1, 5,
          step: (at) => at > 0 ? at - 1 : at, mayPlay: mayPlay);
      expect(back.index, 0);
    });

    test('only explicit songs left: the queue ends there', () {
      final end = playableFrom(3, 5, step: _next(5), mayPlay: mayPlay);
      expect(end.index, isNull);
      expect(end.atEnd, isTrue);
    });

    test('with repeat on, round to the start', () {
      expect(
          playableFrom(3, 5, step: _next(5, repeat: true), mayPlay: mayPlay)
              .index,
          0);
    });

    test('a queue of only explicit songs on repeat: once round, then stop', () {
      var steps = 0;
      final loop = _next(2, repeat: true);
      final none = playableFrom(0, 2,
          step: (at) {
            steps++;
            return loop(at);
          },
          mayPlay: (_) => false);
      expect(none.index, isNull);
      expect(none.atEnd, isFalse);
      expect(steps, 2);
    });
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
        'an explicit song while explicit content is off: dimmed, and '
        'a tap says why instead of playing it', (tester) async {
      var played = 0;
      await pumpRow(tester, _explicit, () => played++);
      expect(_dimmed, findsNothing);
      await tester.tap(find.text('Artist'));
      expect(played, 1);

      await tester.runAsync(() => ExplicitContent.set(false));
      await tester.pump();
      expect(_dimmed, findsOneWidget);
      await tester.tap(find.text('Artist'));
      expect(played, 1);
      expect(player.explained, 1);

      // Allowed again: as it was.
      await tester.runAsync(() => ExplicitContent.set(true));
      await tester.pump();
      expect(_dimmed, findsNothing);
      await tester.tap(find.text('Artist'));
      expect(played, 2);
    });

    testWidgets('a clean song plays as ever', (tester) async {
      await tester.runAsync(() => ExplicitContent.set(false));
      var played = 0;
      await pumpRow(tester, _clean, () => played++);
      expect(_dimmed, findsNothing);
      await tester.tap(find.text('Artist'));
      expect(played, 1);
      expect(player.explained, 0);
    });
  });
}
