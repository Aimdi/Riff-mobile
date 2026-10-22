import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/home_chip.dart';
import 'package:harmonymusic/ui/screens/Home/explore_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/discovery/riff_wave_hero.dart';

class _FakeHome extends GetxController implements HomeScreenController {
  @override
  final middleContent = [].obs;
  @override
  final fixedContent = [].obs;
  @override
  final homeChips = <HomeChip>[].obs;
  @override
  final selectedChip = Rxn<HomeChip>();
  @override
  final chipContent = [].obs;
  @override
  final chipLoading = false.obs;
  @override
  final chipError = false.obs;
  final _controllers = <String, ScrollController>{};
  @override
  ScrollController scrollControllerFor(String key) =>
      _controllers.putIfAbsent(key, ScrollController.new);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Album _album(int i) => Album(
    title: 'Album $i',
    browseId: 'MPRE$i',
    artists: [
      {'name': 'Artist $i'}
    ],
    thumbnailUrl: '');

void main() {
  tearDown(Get.reset);

  testWidgets('Explore shows the genre chips and every shelf', (tester) async {
    tester.view
      ..physicalSize = const Size(411, 918)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final home = Get.put<HomeScreenController>(_FakeHome()) as _FakeHome;
    home.homeChips.assignAll(const [HomeChip(title: 'Relax', params: 'r')]);
    home.fixedContent.assignAll([
      AlbumContent(
          title: 'Albums For You',
          albumList: [for (var i = 0; i < 2; i++) _album(i)]),
      AlbumContent(
          title: 'Throwback Jams',
          albumList: [for (var i = 2; i < 6; i++) _album(i)]),
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: ExploreScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(FilterChip, 'Relax'), findsOneWidget);
    // Nothing is capped or merged here, titles are sentence case.
    expect(find.text('Albums for you'), findsOneWidget);
    expect(find.text('Throwback jams'), findsOneWidget);
    expect(find.text('Album 0'), findsOneWidget);
    // Riff Wave sits on top of the Discover tab's feed, not this page.
    expect(find.byType(RiffWaveHero), findsNothing);
  });

  testWidgets(
      'a genre chip\'s shelves fade in under the chips; the feed shown as '
      'the page opens and the chips stay put', (tester) async {
    tester.view
      ..physicalSize = const Size(411, 918)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final home = Get.put<HomeScreenController>(_FakeHome()) as _FakeHome;
    const relax = HomeChip(title: 'Relax', params: 'r');
    home.homeChips.assignAll(const [relax]);
    home.fixedContent.assignAll([
      AlbumContent(
          title: 'Albums For You',
          albumList: [for (var i = 0; i < 2; i++) _album(i)]),
    ]);
    double opacity(Finder f) {
      final fade = find.ancestor(of: f, matching: find.byType(Opacity));
      return fade.evaluate().isEmpty
          ? 1
          : tester.widget<Opacity>(fade.first).opacity;
    }

    await tester.pumpWidget(const GetMaterialApp(home: ExploreScreen()));
    await tester.pump();
    expect(opacity(find.text('Albums for you')), 1);

    // Picked: its skeleton, then its shelves.
    home.selectedChip.value = relax;
    home.chipLoading.value = true;
    await tester.pump();
    home.chipContent.assignAll([
      AlbumContent(
          title: 'Calm Albums',
          albumList: [for (var i = 2; i < 4; i++) _album(i)]),
    ]);
    home.chipLoading.value = false;
    await tester.pump();
    await tester.pump(RiffDurations.content * 0.5);
    expect(opacity(find.text('Calm albums')), inExclusiveRange(0, 1));
    expect(opacity(find.widgetWithText(FilterChip, 'Relax')), 1);
    await tester.pumpAndSettle();
    expect(opacity(find.text('Calm albums')), 1);
  });
}
