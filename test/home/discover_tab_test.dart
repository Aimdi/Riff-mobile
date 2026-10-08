import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/home_chip.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/screens/Home/discover_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Search/components/search_pill.dart';
import 'package:harmonymusic/ui/widgets/side_nav_bar.dart';
import 'package:harmonymusic/utils/get_localization.dart';

class _FakeHome extends GetxController implements HomeScreenController {
  @override
  final tabIndex = RailTab.home.obs;
  @override
  void onSideBarTabSelected(int index) => tabIndex.value = index;

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

  testWidgets(
      'Discover sits right under Home on the rail and shows search over '
      'the Explore feed', (tester) async {
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
    ]);

    await tester.pumpWidget(GetMaterialApp(
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
    ));

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
}
