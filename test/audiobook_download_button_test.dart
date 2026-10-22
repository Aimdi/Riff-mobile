import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobook_downloads.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_download_button.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    await Hive.openBox(AudiobookDownloads.boxName, bytes: Uint8List(0));
  });
  tearDown(() async {
    AudiobookDownloads.progress.clear();
    await Hive.box(AudiobookDownloads.boxName).close();
  });

  Finder pops() => find.descendant(
      of: find.byType(AudiobookDownloadButton),
      matching: find.byType(ScaleTransition));

  testWidgets('one button whose glyph crossfades; done pops in',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: AudiobookDownloadButton(bookId: 'b', chapters: () => const []),
      ),
    ));
    expect(find.byTooltip('download'), findsOneWidget);

    AudiobookDownloads.progress['b'] = 0.5;
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    // Both glyphs in the one button while they switch; a tap cancels now.
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('cancelDownload'), findsOneWidget);
    expect(pops(), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_for_offline_outlined), findsNothing);

    await tester.runAsync(
        () => Hive.box(AudiobookDownloads.boxName).put('b', {'title': 'B'}));
    AudiobookDownloads.progress.remove('b');
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
    expect(find.byTooltip('removeDownload'), findsOneWidget);
    expect(pops(), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
  });
}
