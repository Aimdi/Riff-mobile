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
}
