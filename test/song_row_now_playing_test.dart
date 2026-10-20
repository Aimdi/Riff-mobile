import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/now_playing_bars.dart';
import 'package:harmonymusic/ui/widgets/song_list_tile.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isCurrentSongFav = false.obs;
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = true.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _song = MediaItem(
    id: 'a', title: 'Song A', artist: 'Artist', extras: {'length': '3:45'});
const _other = MediaItem(id: 'b', title: 'Song B', artist: 'Artist');

/// The playing row's mark easing in and out as the song changes (§4.7),
/// rather than snapping on every track change.
void main() {
  late _FakePlayer player;

  setUp(() {
    player = _FakePlayer();
    Get.put<PlayerController>(player);
    Get.put<SettingsScreenController>(_FakeSettings());
  });
  tearDown(Get.reset);

  Future<void> pumpRow(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(
          body: SongListTile(
              song: _song, thumbReplacementWithIndex: true, index: 1),
        ),
      ));

  Color? titleColor(WidgetTester tester) =>
      tester.widget<Text>(find.text('Song A')).style?.color;

  /// How opaque the row's tint is (0 clear, 255 the full accentMuted).
  int tintAlpha(WidgetTester tester) =>
      (tester
              .widget<DecoratedBox>(find.descendant(
                  of: find.byWidgetPredicate(
                      (w) => w is TweenAnimationBuilder<Color?>),
                  matching: find.byType(DecoratedBox)))
              .decoration as BoxDecoration)
          .color
          ?.alpha ??
      0;

  double lengthTop(WidgetTester tester) =>
      tester.getTopLeft(find.text('3:45')).dy;

  double barsOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(find
          .ancestor(
              of: find.byType(NowPlayingBars),
              matching: find.byType(FadeTransition))
          .first)
      .opacity
      .value;

  testWidgets('becoming the playing row eases its tint, title and bars in',
      (tester) async {
    await pumpRow(tester);
    final context = tester.element(find.byType(SongListTile));
    final accent = Theme.of(context).colorScheme.secondary;
    final full = RiffColors.of(context).accentMuted.alpha;
    final restTitle = titleColor(tester);
    final restTop = lengthTop(tester);
    expect(tintAlpha(tester), 0);
    expect(find.byType(NowPlayingBars), findsNothing);

    player.currentSong.value = _song;
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    // On the way: the title between its colour and the accent, the tint
    // coming up, the bars fading in as the length glides down.
    expect(titleColor(tester), isNot(restTitle));
    expect(titleColor(tester), isNot(accent));
    expect(tintAlpha(tester), inExclusiveRange(0, full));
    expect(barsOpacity(tester), inExclusiveRange(0, 1));
    final midTop = lengthTop(tester);
    expect(midTop, greaterThan(restTop));

    await tester.pumpAndSettle();
    expect(titleColor(tester), accent);
    expect(tintAlpha(tester), full);
    expect(find.byType(NowPlayingBars), findsOneWidget);
    expect(lengthTop(tester), greaterThan(midTop));
  });

  testWidgets('another song starting eases them back out', (tester) async {
    player.currentSong.value = _song;
    await pumpRow(tester);
    final context = tester.element(find.byType(SongListTile));
    final accent = Theme.of(context).colorScheme.secondary;
    // Already playing as it's built: there at once, nothing to ease.
    expect(titleColor(tester), accent);
    expect(find.byType(NowPlayingBars), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    final playingTop = lengthTop(tester);

    player.currentSong.value = _other;
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    expect(titleColor(tester), isNot(accent));
    // The bars fade out where they were before their room closes.
    expect(barsOpacity(tester), inExclusiveRange(0, 1));
    expect(lengthTop(tester), playingTop);

    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingBars), findsNothing);
    expect(tintAlpha(tester), 0);
    expect(lengthTop(tester), lessThan(playingTop));
  });
}
