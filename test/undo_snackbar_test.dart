import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';

void main() {
  // A swiped-away row asks for the snackbar, then is gone before the
  // change is done: Undo must still be offered.
  testWidgets('Undo still shows after the row that asked is gone',
      (tester) async {
    late BuildContext rowContext;
    var showRow = true;
    late StateSetter setList;
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setList = setState;
          return showRow
              ? Builder(builder: (c) {
                  rowContext = c;
                  return const Text('row');
                })
              : const SizedBox.shrink();
        }),
      ),
    ));

    final target = undoSnackbarTarget(rowContext);
    final appTheme = Theme.of(rowContext);
    setList(() => showRow = false);
    await tester.pump();
    expect(rowContext.mounted, isFalse);

    var undone = false;
    final shown =
        showUndoSnackbar(target, 'Removed', onUndo: () => undone = true);
    expect(shown, isNotNull);
    await tester.pumpAndSettle();
    expect(find.text('Removed'), findsOneWidget);
    // Drawn in the app's theme (accent fill), not the fallback theme the
    // messenger itself sits in.
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        appTheme.colorScheme.secondary);

    await tester.tap(find.text('undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(await shown!.closed, SnackBarClosedReason.action);
  });

  testWidgets('a newer change replaces the last snackbar', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: Builder(builder: (c) {
        pageContext = c;
        return const SizedBox.shrink();
      })),
    ));
    final target = undoSnackbarTarget(pageContext);

    final first = showUndoSnackbar(target, 'First', onUndo: () {});
    await tester.pumpAndSettle();
    showUndoSnackbar(target, 'Second', onUndo: () {});
    await tester.pumpAndSettle();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(await first!.closed, SnackBarClosedReason.hide);
  });

  test('nowhere to show it: nothing shown', () {
    expect(showUndoSnackbar(null, 'Removed', onUndo: () {}), isNull);
  });
}
