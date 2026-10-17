import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/components/animated_play_button.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/utils/get_localization.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandler extends BaseAudioHandler {}

void main() {
  setUp(() {
    Get.reset();
    Get.put<MusicServices>(_FakeMusic());
  });
  tearDown(Get.reset);

  testWidgets('the play button says what a tap will do', (tester) async {
    final player = Get.put(PlayerController());
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(GetMaterialApp(
      translations: Languages(),
      locale: const Locale('en'),
      home: const Scaffold(body: Center(child: AnimatedPlayButton())),
    ));

    expect(find.bySemanticsLabel('Play'), findsOneWidget);

    player.buttonState.value = PlayButtonState.playing;
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsNothing);

    semantics.dispose();
    // Close the controller before a handler appears (as in
    // player_controller_lifecycle_test), then let its handler poll end.
    await tester.pumpWidget(const SizedBox());
    Get.delete<PlayerController>();
    Get.put<AudioHandler>(_FakeHandler());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
