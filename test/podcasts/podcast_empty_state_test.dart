import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_empty_state.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';

void main() {
  testWidgets('on a tablet the message keeps to a few short lines',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PodcastEmptyState(
          icon: Icons.block_rounded,
          message: 'Nothing here. Use Never play this from a song\'s menu to '
              'keep a song, artist or album out of your mixes and radio.',
        ),
      ),
    ));
    final message = tester.getRect(find.textContaining('Nothing here'));
    expect(
        message.width, lessThanOrEqualTo(RiffComponentSizes.emptyStateTextMax));
    // Still in the middle of the page.
    expect(message.center.dx, closeTo(640, 1));
  });
}
