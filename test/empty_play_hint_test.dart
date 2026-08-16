import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/empty_play_hint.dart';

void main() {
  test('empty lists offer Wave and Search', () {
    expect(emptyPlayHintActionKeys(), ['riffWave', 'search']);
  });

  testWidgets('empty hint shows the message and both actions', (tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(
        home: Scaffold(
          body: EmptyPlayHint(message: 'No offline songs!'),
        ),
      ),
    );

    expect(find.text('No offline songs!'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
