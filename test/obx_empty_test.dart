import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('Obx with no observables throws (blank Home risk)', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Obx(() => const Scaffold(body: Text('hello'))),
      ),
    );
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('Obx with observable builds', (tester) async {
    final x = true.obs;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Obx(() => Scaffold(body: Text(x.value ? 'yes' : 'no'))),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('yes'), findsOneWidget);
  });
}
