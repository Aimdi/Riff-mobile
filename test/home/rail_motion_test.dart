import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/animated_screen_transition.dart';
import 'package:harmonymusic/ui/widgets/side_nav_bar.dart';

import '../fakes/fake_music_services.dart';

class _FakeHome extends GetxController implements HomeScreenController {
  @override
  final tabIndex = 0.obs;

  @override
  void onSideBarTabSelected(int index,
          {List<int> railOrder = RailTab.phoneRailOrder}) =>
      tabIndex.value = index;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [page] in the page switcher, as the rail or the search filters swap it.
Widget _swap(String page,
        {bool forward = true,
        bool horizontal = false,
        bool enabled = true,
        bool reduce = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
          body: AnimatedScreenTransition(
            enabled: enabled,
            forward: forward,
            horizontalTransition: horizontal,
            child: Center(key: ValueKey(page), child: Text(page)),
          ),
        ),
      ),
    );

/// Swaps [from] for [to] and goes halfway through the swap: how far each
/// page is from its place.
Future<(Offset, Offset)> _halfway(
    WidgetTester tester, Widget from, Widget to) async {
  await tester.pumpWidget(from);
  final place = tester.getCenter(find.text('A'));
  await tester.pumpWidget(to);
  await tester.pump();
  await tester.pump(RiffDurations.page * 0.5);
  return (
    tester.getCenter(find.text('A')) - place,
    tester.getCenter(find.text('B')) - place,
  );
}

void main() {
  group('page swaps', () {
    testWidgets('down the rail: the new page fades through from below',
        (tester) async {
      final (a, b) = await _halfway(tester, _swap('A'), _swap('B'));
      expect(b.dy, greaterThan(0));
      expect(b.dx, 0);
      expect(a.dy, lessThan(0));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
    });

    testWidgets('up the rail: from above', (tester) async {
      final (a, b) = await _halfway(
          tester, _swap('A', forward: false), _swap('B', forward: false));
      expect(b.dy, lessThan(0));
      expect(a.dy, greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('search filters: along the chip row', (tester) async {
      final (a, b) = await _halfway(
          tester, _swap('A', horizontal: true), _swap('B', horizontal: true));
      expect(b.dx, greaterThan(0));
      expect(b.dy, 0);
      expect(a.dx, lessThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('done in the page time, not the old 450 ms', (tester) async {
      await tester.pumpWidget(_swap('A'));
      await tester.pumpWidget(_swap('B'));
      await tester.pump();
      // A frame past the page time (the old swap ran 450 ms).
      await tester.pump(RiffDurations.page + const Duration(milliseconds: 17));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump();
      expect(find.text('A'), findsNothing);
    });

    testWidgets('Remove animations: a fade, no slide', (tester) async {
      await tester.pumpWidget(_swap('A', reduce: true));
      await tester.pumpWidget(_swap('B', reduce: true));
      await tester.pump();
      expect(
          find.ancestor(
              of: find.text('B'),
              matching: find.byWidgetPredicate((w) =>
                  w is Transform && w.transform.getTranslation().length > 0)),
          findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
    });

    testWidgets('transition animation off in settings: at once',
        (tester) async {
      await tester.pumpWidget(_swap('A', enabled: false));
      await tester.pumpWidget(_swap('B', enabled: false));
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('rail direction', () {
    setUp(() => Get.put<MusicServices>(FakeMusicServices()));
    tearDown(Get.reset);

    test('follows the phone rail, where Songs\' items sit above Podcasts', () {
      final home = HomeScreenController();
      home.tabIndex.value = RailTab.playlists;
      // Podcasts (3) is below Playlists (5) on the phone rail.
      home.onSideBarTabSelected(RailTab.podcasts);
      expect(home.reverseAnimationtransiton, isTrue);
      home.onSideBarTabSelected(RailTab.artists);
      expect(home.reverseAnimationtransiton, isFalse);
      home.onSideBarTabSelected(RailTab.settings);
      expect(home.reverseAnimationtransiton, isTrue);
      home.onSideBarTabSelected(RailTab.home);
      expect(home.reverseAnimationtransiton, isFalse);
    });

    test('and the wide rail\'s order when it says so', () {
      final home = HomeScreenController();
      home.tabIndex.value = RailTab.playlists;
      home.onSideBarTabSelected(RailTab.podcasts,
          railOrder: List.generate(9, (i) => i));
      expect(home.reverseAnimationtransiton, isFalse);
    });
  });

  testWidgets('Songs\' sub-items fade out as they fold away, as they came in',
      (tester) async {
    Get.put<HomeScreenController>(_FakeHome());
    addTearDown(Get.reset);
    tester.view
      ..physicalSize = const Size(411, 918)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const GetMaterialApp(
      home: Scaffold(
        body: Row(children: [SideNavBar(), Expanded(child: SizedBox())]),
      ),
    ));
    final caret = find.byIcon(Icons.keyboard_arrow_down_rounded);
    expect(find.bySemanticsLabel('playlists'), findsNothing);

    await tester.tap(caret);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('playlists'), findsOneWidget);
    final open = tester.getSize(find.byType(AnimatedCrossFade)).height;

    await tester.tap(caret);
    await tester.pump();
    await tester.pump(RiffDurations.select * 0.5);
    // Still there, fading and folding (it used to vanish at once).
    final fading = tester
        .widgetList<FadeTransition>(find.ancestor(
            of: find.byIcon(Icons.queue_music),
            matching: find.byType(FadeTransition)))
        .first
        .opacity
        .value;
    expect(fading, greaterThan(0));
    expect(fading, lessThan(1));
    final folding = tester.getSize(find.byType(AnimatedCrossFade)).height;
    expect(folding, greaterThan(0));
    expect(folding, lessThan(open));

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AnimatedCrossFade)).height, 0);
    // Folded away, TalkBack and taps skip them.
    for (final hidden in [ExcludeSemantics, IgnorePointer]) {
      expect(
          find.ancestor(
              of: find.byIcon(Icons.queue_music),
              matching: find.byWidgetPredicate((w) =>
                  w.runtimeType == hidden &&
                  (w is ExcludeSemantics
                      ? w.excluding
                      : (w as IgnorePointer).ignoring))),
          findsWidgets,
          reason: '$hidden');
    }
    semantics.dispose();
  });
}
