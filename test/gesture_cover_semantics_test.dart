import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/gesture_player.dart';

void main() {
  testWidgets("the cover's gestures are screen reader actions", (tester) async {
    final handle = tester.ensureSemantics();
    final calls = <String>[];
    Widget cover({required bool playing}) => MaterialApp(
          home: GestureCoverSemantics(
            playing: playing,
            onNext: () => calls.add('next'),
            onPrevious: () => calls.add('previous'),
            onPlayPause: () => calls.add('playPause'),
            onOptions: () => calls.add('options'),
            child: const SizedBox.expand(),
          ),
        );

    await tester.pumpWidget(cover(playing: true));
    final node = find.semantics.byLabel('coverArt');
    expect(node, findsOne);
    expect(
      tester.getSemantics(find.byType(GestureCoverSemantics)),
      containsSemantics(
        label: 'coverArt',
        isImage: true,
        hasLongPressAction: true,
        customActions: const [
          CustomSemanticsAction(label: 'pause'),
          CustomSemanticsAction(label: 'next'),
          CustomSemanticsAction(label: 'previous'),
        ],
      ),
    );

    for (final label in ['next', 'previous', 'pause']) {
      tester.semantics.performAction(node, SemanticsAction.customAction,
          args: CustomSemanticsAction.getIdentifier(
              CustomSemanticsAction(label: label)));
    }
    tester.semantics.performAction(node, SemanticsAction.longPress);
    expect(calls, ['next', 'previous', 'playPause', 'options']);

    // Paused, the action says Play.
    await tester.pumpWidget(cover(playing: false));
    expect(
      tester.getSemantics(find.byType(GestureCoverSemantics)),
      containsSemantics(customActions: const [
        CustomSemanticsAction(label: 'play'),
        CustomSemanticsAction(label: 'next'),
        CustomSemanticsAction(label: 'previous'),
      ]),
    );
    handle.dispose();
  });
}
