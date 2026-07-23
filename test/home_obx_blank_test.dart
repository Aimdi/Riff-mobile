import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Documents the blank-startup regression from removing bottom-nav:
/// Home wrapped Scaffold in Obx that previously read isBottomNavBarEnabled.
/// On phones endDrawer is null, so that Obx read zero observables and GetX
/// threw — blank light-gray release screen with working status bar only.
void main() {
  testWidgets(
      'phone-width Scaffold Obx with no observables throws (pre-fix pattern)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      GetMaterialApp(
        home: Obx(
          () => const Scaffold(
            // Mirrors post-bottom-nav Home on phone: endDrawer null, no
            // bottomNavigationBar observable reads in this Obx scope.
            endDrawer: null,
            body: Center(child: Text('home-body')),
          ),
        ),
      ),
    );

    // GetX throws during build; ErrorWidget / exception = blank Home.
    expect(tester.takeException(), isNotNull);
  });

  testWidgets(
      'Scaffold without outer Obx builds on phone (post-fix pattern)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final panelMin = 0.0.obs;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          endDrawer: null,
          body: Obx(
            () => SizedBox(
              height: panelMin.value + 100,
              child: const Center(child: Text('home-body')),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('home-body'), findsOneWidget);
  });

  testWidgets(
      'HomeScreen body Obx with no observables blanks rail+content (pre-1.7.73)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final tabIndex = 0.obs;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          // FAB Obx still has observables → green search button still shows.
          floatingActionButton: Obx(
            () => tabIndex.value == 0
                ? const FloatingActionButton(onPressed: null, child: Icon(Icons.search))
                : const SizedBox.shrink(),
          ),
          // Body Obx used to gate SideNavBar on isBottomNavBarEnabled; after
          // always-showing SideNavBar it read zero Rx → GetX blank.
          body: Obx(
            () => const Row(
              children: [
                SizedBox(width: 48, child: Text('rail')),
                Expanded(child: Text('home-content')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNotNull);
  });

  testWidgets(
      'HomeScreen Row without empty Obx shows rail and content (1.7.73)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final tabIndex = 0.obs;
    final transitionOff = false.obs;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          floatingActionButton: Obx(
            () => tabIndex.value == 0
                ? const FloatingActionButton(onPressed: null, child: Icon(Icons.search))
                : const SizedBox.shrink(),
          ),
          body: Row(
            children: [
              const SizedBox(width: 48, child: Text('rail')),
              Expanded(
                child: Obx(
                  () => Text(
                    transitionOff.value ? 'home-content-static' : 'home-content',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('rail'), findsOneWidget);
    expect(find.text('home-content'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets(
      'SearchScreen outer Obx with no observables blanks search (pre-1.7.74)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final suggestions = <String>[].obs;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          // Outer Obx used to read isBottomNavBarEnabled for the back rail;
          // after always-showing rail it read zero Rx → blank Search.
          body: Obx(
            () => Row(
              children: [
                const SizedBox(width: 60, child: Text('back')),
                Expanded(
                  child: Obx(
                    () => Text(
                      suggestions.isEmpty ? 'search-empty' : 'search-list',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNotNull);
  });

  testWidgets(
      'SearchScreen Row without empty outer Obx shows search UI (1.7.74)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final suggestions = <String>[].obs;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 60, child: Text('back')),
              Expanded(
                child: Obx(
                  () => Text(
                    suggestions.isEmpty ? 'search-empty' : 'search-list',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('back'), findsOneWidget);
    expect(find.text('search-empty'), findsOneWidget);
  });
}
