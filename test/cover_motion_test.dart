import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/collection_header.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
import 'package:harmonymusic/ui/widgets/shimmer_widgets/basic_container.dart';

Widget _app(Widget child) => GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: Center(child: child)),
    );

Album _album(String thumb) => Album(
    title: 'LP', browseId: 'MPREb_1', thumbnailUrl: thumb, artists: const []);

/// The opacity [text] fades at (the nearest FadeTransition above it).
double _fadeOf(WidgetTester tester, String text) => tester
    .widget<FadeTransition>(find
        .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
        .first)
    .opacity
    .value;

void main() {
  group('covers', () {
    testWidgets(
        'fade in on Riff\'s timing, the placeholder clearing as fast, '
        'and pulse like the skeletons while loading', (tester) async {
      await tester.pumpWidget(_app(ImageWidget(
          album: _album('https://lh3.googleusercontent.com/a=w120-h120'),
          size: 120)));
      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.fadeInDuration, RiffDurations.image);
      expect(image.fadeInCurve, RiffDurations.enterCurve);
      expect(image.fadeOutDuration, RiffDurations.image);
      expect(image.fadeOutCurve, RiffDurations.enterCurve);
      expect(find.byType(RiffSkeletonPulse), findsOneWidget);
    });

    testWidgets(
        'a new URL for the same album keeps the old image up while it '
        'loads; another album starts afresh', (tester) async {
      await tester.pumpWidget(_app(ImageWidget(
          album: _album('https://lh3.googleusercontent.com/a=w120-h120'),
          size: 120)));
      final cover =
          tester.widget<RiffNetworkImage>(find.byType(RiffNetworkImage));
      expect(cover.useOldImageOnUrlChange, isTrue);
      expect(cover.key, const ValueKey('MPREb_1'));
      final element = tester.element(find.byType(CachedNetworkImage));

      await tester.pumpWidget(_app(ImageWidget(
          album: _album('https://lh3.googleusercontent.com/b=w120-h120'),
          size: 120)));
      // The same image element, so it crossfades from the old URL.
      expect(tester.element(find.byType(CachedNetworkImage)), same(element));

      await tester.pumpWidget(_app(ImageWidget(
          album: Album(
              title: 'EP',
              browseId: 'MPREb_2',
              thumbnailUrl: 'https://lh3.googleusercontent.com/b=w120-h120',
              artists: const []),
          size: 120)));
      expect(tester.element(find.byType(CachedNetworkImage)),
          isNot(same(element)));
    });
  });

  group('collection header', () {
    testWidgets('the top bar\'s title and back-button scrim ease over',
        (tester) async {
      Widget bar(bool showTitle) =>
          _app(CollectionTopBar(title: 'Album', showTitle: showTitle));
      Color scrim() => tester
          .widget<Material>(find
              .ancestor(
                  of: find.byType(IconButton), matching: find.byType(Material))
              .first)
          .color!;

      await tester.pumpWidget(bar(false));
      final over = scrim();
      expect(over.opacity, greaterThan(0));

      await tester.pumpWidget(bar(true));
      await tester.pump(RiffDurations.select ~/ 2);
      expect(scrim().opacity, inExclusiveRange(0, over.opacity));
      expect(_fadeOf(tester, 'Album'), inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(scrim().opacity, 0);
      expect(_fadeOf(tester, 'Album'), 1);
    });

    testWidgets('saving crossfades the plus into the check', (tester) async {
      Widget save(bool saved) =>
          _app(CollectionSaveButton(saved: saved, onPressed: () {}));
      await tester.pumpWidget(save(false));
      await tester.pumpWidget(save(true));
      await tester.pump(RiffDurations.select ~/ 2);
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });
}
