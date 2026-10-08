import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/home_chip.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/models/quick_picks.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Home/discover_screen.dart';
import 'package:harmonymusic/ui/screens/Home/explore_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Home/home_station_chips.dart';
import 'package:harmonymusic/ui/screens/Search/components/search_pill.dart';
import 'package:harmonymusic/ui/widgets/discovery/riff_wave_hero.dart';
import 'package:harmonymusic/ui/widgets/side_nav_bar.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

class _FakeHome extends GetxController implements HomeScreenController {
  @override
  final tabIndex = RailTab.home.obs;
  @override
  void onSideBarTabSelected(int index) => tabIndex.value = index;

  @override
  final quickPicks = QuickPicks([]).obs;
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

/// What the Riff Wave card reads; counts the times Wave is started.
class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  final playinfrom = PlaylingFrom(type: PlaylingFromType.SELECTION).obs;
  @override
  final playerPanelMinHeight = 0.0.obs;

  int waveStarts = 0;
  @override
  Future<bool> startRiffWave() async {
    waveStarts++;
    return true;
  }

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

Widget _app(_FakeHome home) => GetMaterialApp(
      translations: Languages(),
      locale: const Locale('en'),
      home: Navigator(
        key: Get.nestedKey(ScreenNavigationSetup.id),
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => settings.name == ScreenNavigationSetup.searchScreen
              ? const Scaffold(body: Text('search screen'))
              : Scaffold(
                  body: Row(children: [
                    const SideNavBar(),
                    // The real tab switcher, for every tab but Home (whose
                    // feed needs the app's services).
                    Expanded(
                      child: Obx(() => home.tabIndex.value == RailTab.home
                          ? const SizedBox.shrink()
                          : Body(key: ValueKey(home.tabIndex.value))),
                    ),
                  ]),
                ),
        ),
      ),
    );

_FakeHome _putFakes() {
  Get.put<PlayerController>(_FakePlayer());
  final home = Get.put<HomeScreenController>(_FakeHome()) as _FakeHome;
  home.homeChips.assignAll(const [HomeChip(title: 'Relax', params: 'r')]);
  home.fixedContent.assignAll([
    AlbumContent(
        title: 'Albums For You',
        albumList: [for (var i = 0; i < 2; i++) _album(i)]),
    // Enough feed below to scroll.
    for (var n = 1; n <= 4; n++)
      AlbumContent(
          title: 'More albums $n',
          albumList: [for (var i = 0; i < 2; i++) _album(10 * n + i)]),
  ]);
  return home;
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    // The Wave card falls back to the most recently played song (stats).
    tmp = await Directory.systemTemp.createTemp('riff_discover_tab_');
    Hive.init(tmp.path);
    await Hive.openBox('SongStats');
    await Hive.openBox('DailyStats');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  tearDown(Get.reset);

  testWidgets(
      'Discover sits right under Home on the rail and shows search over '
      'the Explore feed', (tester) async {
    tester.view
      ..physicalSize = const Size(411, 918)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final home = _putFakes();

    await tester.pumpWidget(_app(home));

    Finder rail(Finder f) =>
        find.descendant(of: find.byType(SideNavBar), matching: f);
    double railY(String label) => tester.getCenter(rail(find.text(label))).dy;

    // Home, then Discover (compass), then Songs.
    expect(railY('Home'), lessThan(railY('Discover')));
    expect(railY('Discover'), lessThan(railY('Songs')));
    expect(rail(find.byIcon(Icons.explore_outlined)), findsOneWidget);
    expect(find.byType(DiscoverScreen), findsNothing);

    await tester.tap(rail(find.text('Discover')));
    await tester.pumpAndSettle();

    expect(home.tabIndex.value, RailTab.discover);
    expect(rail(find.byIcon(Icons.explore_rounded)), findsOneWidget);
    expect(find.byType(DiscoverScreen), findsOneWidget);
    // The search field on top, with the search screen's hint...
    final field = find.byType(SearchLauncherField);
    expect(field, findsOneWidget);
    expect(find.text('Songs, Playlist, Album or Artist'), findsOneWidget);
    // ...and the Explore feed below it.
    final chip = find.widgetWithText(FilterChip, 'Relax');
    expect(chip, findsOneWidget);
    expect(find.text('Albums for you'), findsOneWidget);
    expect(tester.getBottomLeft(field).dy,
        lessThanOrEqualTo(tester.getTopLeft(chip).dy));

    // A tap opens the Search screen, as the Home header's search did.
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('search screen'), findsOneWidget);
  });

  for (final size in const [Size(411, 918), Size(360, 740)]) {
    testWidgets(
        'Discover shows the Riff Wave card and its stations at the top of '
        'the feed (${size.width.toInt()}x${size.height.toInt()})',
        (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final home = _putFakes();
      await tester.pumpWidget(_app(home));
      home.onSideBarTabSelected(RailTab.discover);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final wave = find.byType(RiffWaveHero);
      expect(wave, findsOneWidget);
      expect(find.text('Riff Wave'), findsOneWidget);
      expect(
          find.text('A station from what you actually play'), findsOneWidget);
      final station = find.text('Fresh finds');
      expect(station, findsOneWidget);
      expect(find.byType(RiffStationChips), findsOneWidget);

      // Search, then Wave, then its stations, then YouTube's genre chips.
      final field = find.byType(SearchLauncherField);
      final genre = find.widgetWithText(FilterChip, 'Relax');
      expect(tester.getBottomLeft(field).dy,
          lessThanOrEqualTo(tester.getTopLeft(wave).dy));
      expect(tester.getBottomLeft(wave).dy,
          lessThanOrEqualTo(tester.getTopLeft(station).dy));
      expect(tester.getBottomLeft(station).dy,
          lessThanOrEqualTo(tester.getTopLeft(genre).dy));
      // The card has the search field's gutters.
      final card =
          find.descendant(of: wave, matching: find.byType(Material)).first;
      expect(tester.getTopLeft(card).dx, tester.getTopLeft(field).dx);
      expect(tester.getTopRight(card).dx, tester.getTopRight(field).dx);

      // It is part of the feed (scrolls with it), not a fixed block, and
      // it leaves the feed most of a small screen.
      expect(find.ancestor(of: wave, matching: find.byType(ExploreFeed)),
          findsOneWidget);
      expect(tester.getTopLeft(genre).dy, lessThan(size.height * 0.6));
      final waveTop = tester.getTopLeft(wave).dy;
      final fieldTop = tester.getTopLeft(field).dy;
      await tester.drag(find.text('Albums for you'), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(wave).dy, lessThan(waveTop));
      expect(tester.getTopLeft(field).dy, fieldTop);
    });
  }

  testWidgets('the Wave card in Discover starts Riff Wave', (tester) async {
    tester.view
      ..physicalSize = const Size(411, 918)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final home = _putFakes();
    await tester.pumpWidget(_app(home));
    home.onSideBarTabSelected(RailTab.discover);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(RiffWaveHero));
    await tester.pumpAndSettle();
    expect((Get.find<PlayerController>() as _FakePlayer).waveStarts, 1);
  });
}
