import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_bookmarks.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_bookmarks_ui.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/get_localization.dart';

const _bm = PodcastBookmark(
    id: 'bm1', episodeId: 'podcast_1', positionMs: 1000, createdAt: 1);

void main() {
  // No Hive box is open, so saving the note is a no-op here: this is about
  // the dialog itself.
  for (final button in ['Save', 'Cancel']) {
    // Closing used to throw "A TextEditingController was used after being
    // disposed": the controller was disposed while the dialog animated out.
    testWidgets('the note dialog closes cleanly with $button', (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        translations: Languages(),
        locale: const Locale('en'),
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editBookmarkNote(context, _bm),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Great quote');
      await tester.pump();
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    });
  }
}
