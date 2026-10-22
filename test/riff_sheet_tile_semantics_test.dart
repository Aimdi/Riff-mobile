import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/cust_switch.dart';
import 'package:harmonymusic/ui/widgets/riff_sheet.dart';

void main() {
  testWidgets('a sheet row with a switch is one labelled toggle for TalkBack',
      (tester) async {
    final handle = tester.ensureSemantics();
    var on = false;
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => RiffSheetTile(
            icon: Icons.vibration_rounded,
            title: 'Shake to restart',
            subtitle: 'Shake the phone to start the timer again',
            onTap: () => setState(() => on = !on),
            trailing: CustSwitch(
                value: on, onChanged: (v) => setState(() => on = v)),
          ),
        ),
      ),
    ));

    final node = tester.getSemantics(find.byType(RiffSheetTile));
    final data = node.getSemanticsData();
    expect(data.label, contains('Shake to restart'));
    expect(data.hasFlag(SemanticsFlag.hasToggledState), isTrue);
    expect(data.hasFlag(SemanticsFlag.isToggled), isFalse);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    // TalkBack's double tap toggles it.
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(on, isTrue);
    handle.dispose();
  });
}
