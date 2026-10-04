import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/side_nav_bar.dart';

class _FakeHome extends GetxController implements HomeScreenController {
  @override
  final tabIndex = 0.obs;

  @override
  void onSideBarTabSelected(int index) => tabIndex.value = index;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => Get.put<HomeScreenController>(_FakeHome()));
  tearDown(Get.reset);

  testWidgets('rail keeps its width when Songs expands; every item is labelled',
      (tester) async {
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

    double railWidth() => tester.getSize(find.byType(SideNavBar)).width;
    expect(railWidth(), kRailWidth);

    for (final label in [
      'home',
      'songs',
      'podcasts',
      'audiobooks',
      'settings'
    ]) {
      expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
    }

    // The caret is a 48dp-tall, full-width target.
    final caret = find.byIcon(Icons.keyboard_arrow_down_rounded);
    final target =
        find.ancestor(of: caret, matching: find.byType(InkWell)).first;
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));

    await tester.tap(caret);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('playlists'), findsOneWidget);
    expect(railWidth(), kRailWidth);
    semantics.dispose();
  });
}
