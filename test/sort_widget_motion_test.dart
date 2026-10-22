import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/riff_motion.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';

class _Screen extends GetxController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  tearDown(Get.reset);

  Widget bar({bool downloadedOnly = false}) => MaterialApp(
        home: Scaffold(
          body: SortWidget(
            tag: 'motion',
            itemCountTitle: 'Songs',
            screenController: _Screen(),
            isSearchFeatureRequired: true,
            isDownloadedFilterRequired: true,
            isDownloadedOnly: downloadedOnly,
            onDownloadedToggle: () {},
            onSearchStart: (_) {},
            onSearch: (_, __) {},
            onSearchClose: (_) {},
            onSort: (_, __) {},
          ),
        ),
      );

  testWidgets('the row and the search field crossfade', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(find.byTooltip('search'));
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    // Both while they switch.
    expect(find.text('Songs'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Songs'), findsNothing);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    // As tall as the bar, as it was on its own.
    expect(tester.getSize(find.byType(TextField)).height,
        tester.getSize(find.byType(RiffSwitcher).first).height);

    await tester.tap(find.byTooltip('close'));
    await tester.pump();
    // Fading out, it has already let go of the keyboard.
    expect(find.byType(TextField), findsOneWidget);
    expect(field.focusNode.hasFocus, isFalse);

    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Songs'), findsOneWidget);
  });

  testWidgets('filters are labelled chips over the bar (Spotify)',
      (tester) async {
    var toggles = 0;
    Widget chips({bool on = false}) => MaterialApp(
          home: Scaffold(
            body: SortWidget(
              tag: 'chips',
              itemCountTitle: 'Songs',
              screenController: _Screen(),
              isDownloadedFilterRequired: true,
              isDownloadedOnly: on,
              onDownloadedToggle: () => toggles++,
              isCloudFeatureRequired: true,
              isCloudModeActive: false,
              onCloudToggle: () {},
              onSort: (_, __) {},
            ),
          ),
        );
    await tester.pumpWidget(chips());
    final downloaded = find.widgetWithText(FilterChip, 'downloaded');
    expect(downloaded, findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'cloud'), findsOneWidget);
    expect(tester.widget<FilterChip>(downloaded).selected, isFalse);
    // Not in the bar any more as bare icons.
    expect(find.byTooltip('downloadedOnly'), findsNothing);

    await tester.tap(downloaded);
    expect(toggles, 1);

    await tester.pumpWidget(chips(on: true));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(downloaded).selected, isTrue);
  });
}
