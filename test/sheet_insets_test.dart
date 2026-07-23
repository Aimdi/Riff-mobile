import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/utils/sheet_insets.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('safe-area only when not lifting above mini player',
      (tester) async {
    late double inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 24)),
        child: Builder(builder: (context) {
          inset = sheetBottomInset(context, liftAboveMiniPlayer: false);
          return const SizedBox();
        }),
      ),
    );
    expect(inset, 24);
  });

  testWidgets('falls back to safe area without PlayerController',
      (tester) async {
    late double inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 16)),
        child: Builder(builder: (context) {
          inset = sheetBottomInset(context);
          return const SizedBox();
        }),
      ),
    );
    expect(inset, 16);
  });
}
