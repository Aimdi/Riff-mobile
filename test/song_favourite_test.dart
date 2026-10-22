import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/song_favourite.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isCurrentSongFav = false.obs;
  final liked = <String, bool>{};

  @override
  Future<void> toggleFavouriteFor(MediaItem song, {bool? adding}) async {
    liked[song.id] = adding ?? !(liked[song.id] ?? false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _song = MediaItem(id: 'a', title: 'Song A');

void main() {
  test('row heart ignores a second tap inside the debounce window', () {
    final first = DateTime(2026, 1, 1, 12, 0, 0);
    expect(shouldIgnoreHeartToggle(null, first), isFalse);
    expect(
      shouldIgnoreHeartToggle(
        first,
        first.add(const Duration(milliseconds: 399)),
      ),
      isTrue,
    );
    expect(
      shouldIgnoreHeartToggle(
        first,
        first.add(const Duration(milliseconds: 400)),
      ),
      isFalse,
    );
  });

  group('the row heart', () {
    late _FakePlayer player;
    setUp(() {
      player = _FakePlayer();
      Get.put<PlayerController>(player);
    });
    tearDown(Get.reset);

    Future<void> pumpHeart(WidgetTester tester) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(
              body: Center(child: SongRowHeartButton(song: _song))),
        ));

    Finder pops() => find.descendant(
        of: find.byType(SongRowHeartButton),
        matching: find.byType(ScaleTransition));

    testWidgets('a like pops the filled heart in', (tester) async {
      await pumpHeart(tester);
      expect(pops(), findsNothing);

      await tester.tap(find.byType(SongRowHeartButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(player.liked['a'], isTrue);
      // Both while it switches, the new one growing in.
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(pops(), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('an unlike only crossfades', (tester) async {
      player.currentSong.value = _song;
      player.isCurrentSongFav.value = true;
      await pumpHeart(tester);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      player.isCurrentSongFav.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(pops(), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsNothing);
    });
  });
}
