import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/theme/palettes/generated_covers.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/content_list_widget_item.dart';
import 'package:harmonymusic/ui/widgets/generated_cover.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
import 'package:harmonymusic/ui/widgets/letter_art.dart';

Widget _app(Widget child) => GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: Center(child: child)),
    );

Finder _coverTitle(String title) => find.descendant(
    of: find.byType(GeneratedCover), matching: find.text(title));

void main() {
  tearDown(GeneratedCoverCache.clear);

  group('recipe', () {
    test('FNV-1a hash matches the reference values (stable across runs)', () {
      expect(GeneratedCoverRecipe.hashOf(''), 0x811C9DC5);
      expect(GeneratedCoverRecipe.hashOf('a'), 0xE40C292C);
      expect(GeneratedCoverRecipe.hashOf('foobar'), 0xBF9CF968);
    });

    test('the same seed always gives the same palette and layout', () {
      final a = GeneratedCoverRecipe.forSeed('PLrAXtmErZgOei');
      final b = GeneratedCoverRecipe.forSeed('PLrAXtmErZgOei');
      expect(a, b);
      expect(a.paletteIndex, b.paletteIndex);
      expect(a.blobs.map((e) => e.center), b.blobs.map((e) => e.center));
    });

    test('different ids give different covers, spread over the palettes', () {
      final ids = [for (var i = 0; i < 60; i++) 'LOCAL_${1700000000 + i}'];
      final recipes = ids.map(GeneratedCoverRecipe.forSeed).toList();
      expect(recipes.toSet().length, ids.length);
      // Ids one character apart still land on different layouts.
      expect(
          recipes[0].blobs.first.center, isNot(recipes[1].blobs.first.center));
      final palettes = recipes.map((r) => r.paletteIndex).toSet();
      expect(palettes.length, greaterThanOrEqualTo(10));
    });

    test('blob colours come from the chosen palette', () {
      final r = GeneratedCoverRecipe.forSeed('PLx');
      final p = r.palette;
      expect(r.base, p.base);
      for (final b in r.blobs) {
        expect(
            [p.base, p.primary, p.secondary, p.highlight], contains(b.color));
      }
    });

    test('there are at least ten curated palettes', () {
      expect(GeneratedCoverPalettes.all.length, greaterThanOrEqualTo(10));
    });

    test('a playlist is seeded by its id, else its title', () {
      expect(
          GeneratedCover.seedOf(
              Playlist(title: 'Chill', playlistId: 'PL1', thumbnailUrl: '')),
          'PL1');
      expect(
          GeneratedCover.seedOf(
              Playlist(title: 'Chill', playlistId: ' ', thumbnailUrl: '')),
          'Chill');
    });

    test('raster sizes are bucketed', () {
      expect(GeneratedCoverCache.rasterSizeFor(10), 96);
      expect(GeneratedCoverCache.rasterSizeFor(144), 160);
      expect(GeneratedCoverCache.rasterSizeFor(384), 384);
      expect(GeneratedCoverCache.rasterSizeFor(5000), 1024);
    });
  });

  group('Playlist.hasArt', () {
    test('no url and the shared placeholder are no art', () {
      Playlist pl(String url) =>
          Playlist(title: 't', playlistId: 'p', thumbnailUrl: url);
      expect(pl('').hasArt, isFalse);
      expect(pl(Playlist.thumbPlaceholderUrl).hasArt, isFalse);
      expect(
          pl('https://lh3.googleusercontent.com/x=w544-h544').hasArt, isTrue);
    });
  });

  group('GeneratedCover widget', () {
    testWidgets('prints the title on a large cover', (tester) async {
      await tester.pumpWidget(_app(const GeneratedCover(
          seed: 'PL1', title: 'Late Night Drive', size: 160)));
      expect(_coverTitle('Late Night Drive'), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('omits the title on row-sized art', (tester) async {
      await tester
          .pumpWidget(_app(Column(mainAxisSize: MainAxisSize.min, children: [
        for (final size in [
          RiffComponentSizes.rowArt,
          RiffComponentSizes.wideRowArt,
          RiffComponentSizes.collectionArt,
        ])
          GeneratedCover(seed: 'PL1', title: 'Late Night Drive', size: size),
      ])));
      expect(find.byType(GeneratedCover), findsNWidgets(3));
      expect(find.text('Late Night Drive'), findsNothing);
      expect(find.byType(RawImage), findsNWidgets(3));
    });

    testWidgets('showTitle: false hides it at any size', (tester) async {
      await tester.pumpWidget(_app(const GeneratedCover(
          seed: 'PL1',
          title: 'Late Night Drive',
          size: 300,
          showTitle: false)));
      expect(find.text('Late Night Drive'), findsNothing);
    });

    testWidgets('the title is not read out twice by screen readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          _app(const GeneratedCover(seed: 'PL1', title: 'Focus', size: 160)));
      expect(find.bySemanticsLabel('Focus'), findsNothing);
      handle.dispose();
    });

    testWidgets('one drawn image per seed and size, shared between covers',
        (tester) async {
      await tester.pumpWidget(
          _app(const Column(mainAxisSize: MainAxisSize.min, children: [
        GeneratedCover(seed: 'PLa', title: 'A', size: 48),
        GeneratedCover(seed: 'PLa', title: 'A', size: 48),
        GeneratedCover(seed: 'PLb', title: 'B', size: 48),
      ])));
      expect(GeneratedCoverCache.length, 2);
      // Rebuilding (as a scrolling list does) draws nothing new.
      await tester.pumpWidget(
          _app(const Column(mainAxisSize: MainAxisSize.min, children: [
        GeneratedCover(seed: 'PLb', title: 'B', size: 48),
        GeneratedCover(seed: 'PLa', title: 'A', size: 48),
      ])));
      expect(GeneratedCoverCache.length, 2);
      // Removing the covers keeps the cached images usable.
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pumpWidget(
          _app(const GeneratedCover(seed: 'PLa', title: 'A', size: 48)));
      expect(GeneratedCoverCache.length, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cache stays within its memory budget', (tester) async {
      final handles = [
        for (var i = 0; i < 12; i++) GeneratedCoverCache.obtain('PL$i', 1024),
      ];
      const perImage = 1024 * 1024 * 4;
      expect(GeneratedCoverCache.length,
          lessThanOrEqualTo(RiffCoverArt.cacheBytes ~/ perImage));
      // Least recently used go first.
      expect(GeneratedCoverCache.contains('PL11', 1024), isTrue);
      expect(GeneratedCoverCache.contains('PL0', 1024), isFalse);
      // Handles given out stay valid after their cache entry is dropped.
      expect(handles.first.debugDisposed, isFalse);
      for (final h in handles) {
        h.dispose();
      }
    });
  });

  group('title fit', () {
    TextStyle large() => RiffTextStyles.forColor(Colors.white).coverTitle;
    TextStyle compact() =>
        RiffTextStyles.forColor(Colors.white).coverTitleCompact;

    test('short titles use the large style over two lines', () {
      final fit = GeneratedCoverTitleFit.of(
          'Chill Vibes', large(), compact(), TextDirection.ltr);
      expect(fit.compact, isFalse);
      expect(fit.maxLines, RiffCoverArt.titleMaxLines);
      expect(fit.scale, 1);
    });

    test('long titles switch to the compact style over three lines', () {
      final fit = GeneratedCoverTitleFit.of(
          'My Favourite Songs Of All Time Forever And Ever',
          large(),
          compact(),
          TextDirection.ltr);
      expect(fit.compact, isTrue);
      expect(fit.maxLines, RiffCoverArt.titleMaxLinesCompact);
    });

    test('a word too wide for the cover shrinks instead of splitting', () {
      final fit = GeneratedCoverTitleFit.of(
          'Supercalifragilisticexpialidocious',
          large(),
          compact(),
          TextDirection.ltr);
      expect(fit.compact, isTrue);
      expect(fit.scale, lessThan(1));
    });
  });

  group('ImageWidget', () {
    testWidgets('a playlist without art gets its generated cover',
        (tester) async {
      final pl = Playlist(
          title: 'Road Trip',
          playlistId: 'LOCAL_1',
          thumbnailUrl: Playlist.thumbPlaceholderUrl,
          isCloudPlaylist: false);
      await tester.pumpWidget(_app(ImageWidget(playlist: pl, size: 160)));
      final cover = tester.widget<GeneratedCover>(find.byType(GeneratedCover));
      expect(cover.seed, 'LOCAL_1');
      expect(_coverTitle('Road Trip'), findsOneWidget);
      expect(find.byType(LetterArt), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('an empty thumbnail counts as no art too', (tester) async {
      await tester.pumpWidget(_app(ImageWidget(
          playlist: Playlist(title: 'Mix', playlistId: 'PL2', thumbnailUrl: ''),
          size: RiffComponentSizes.rowArt)));
      expect(find.byType(GeneratedCover), findsOneWidget);
      expect(find.text('Mix'), findsNothing);
    });

    testWidgets('a playlist with art shows the image', (tester) async {
      await tester.pumpWidget(_app(ImageWidget(
          playlist: Playlist(
              title: 'Hits',
              playlistId: 'PL3',
              thumbnailUrl: 'https://lh3.googleusercontent.com/abc=w544-h544'),
          size: 160)));
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.byType(GeneratedCover), findsNothing);
    });

    testWidgets('albums and podcast shows keep the letter tile',
        (tester) async {
      await tester
          .pumpWidget(_app(Column(mainAxisSize: MainAxisSize.min, children: [
        ImageWidget(
            album: Album(
                title: 'LP',
                browseId: 'MPREb_1',
                thumbnailUrl: Playlist.thumbPlaceholderUrl,
                artists: const []),
            size: 120),
        ImageWidget(
            playlist: Playlist(
                title: 'Show',
                playlistId: 'MPSPshow',
                thumbnailUrl: Playlist.thumbPlaceholderUrl,
                kind: 'podcast'),
            size: 120),
      ])));
      expect(find.byType(GeneratedCover), findsNothing);
      expect(find.byType(LetterArt), findsNWidgets(2));
    });
  });

  testWidgets('a library playlist tile uses the generated cover',
      (tester) async {
    await tester.pumpWidget(_app(ContentListItem(
      content: Playlist(
        title: 'Gym Bangers',
        playlistId: 'LOCAL_9',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      ),
      isLibraryItem: true,
      size: 128,
    )));
    expect(find.byType(GeneratedCover), findsOneWidget);
    expect(_coverTitle('Gym Bangers'), findsOneWidget);
    // The tile's own label is still there under the cover.
    expect(find.text('Gym Bangers'), findsNWidgets(2));
  });
}
