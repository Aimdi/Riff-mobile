import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/favorite_heart_button.dart';

void main() {
  test('medium press is between a tap and default long-press', () {
    final ms = FavoriteHeartButton.mediumPress.inMilliseconds;
    expect(ms, greaterThan(200));
    expect(ms, lessThan(500));
  });

  test('heart toggle debounce is longer than a double-tap gap', () {
    expect(
      FavoriteHeartButton.toggleDebounce.inMilliseconds,
      greaterThanOrEqualTo(300),
    );
  });

  group('the heart', () {
    late RxBool fav;
    late Rxn<MediaItem> song;
    setUp(() {
      fav = false.obs;
      song = Rxn<MediaItem>(const MediaItem(id: 'a', title: 'A'));
    });

    Future<void> pumpHeart(WidgetTester tester) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(
            body: Center(
              child: FavoriteHeartButton(
                isFav: fav,
                onToggleFav: fav.toggle,
                song: () => song.value,
              ),
            ),
          ),
        ));

    Finder pops() => find.descendant(
        of: find.byType(FavoriteHeartButton),
        matching: find.byType(ScaleTransition));

    testWidgets('a like pops in; an unlike only crossfades', (tester) async {
      await pumpHeart(tester);

      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(fav.isTrue, isTrue);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(pops(), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsNothing);

      fav.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(pops(), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('the next song\'s heart shows as it is, without a pop',
        (tester) async {
      await pumpHeart(tester);
      song.value = const MediaItem(id: 'b', title: 'B');
      fav.value = true;
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
