import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/widgets/piped_sync_widget.dart';
import 'package:harmonymusic/utils/get_localization.dart';

/// The Playlists tab controller as far as the sync button uses it.
class _FakeLibrary extends GetxController
    with GetTickerProviderStateMixin
    implements LibraryPlaylistsController {
  _FakeLibrary(this.fail);
  final bool fail;

  @override
  late final AnimationController controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 5));

  @override
  Future<bool> syncPipedPlaylist() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (fail) throw Exception('offline');
    return true;
  }

  @override
  void onClose() {
    controller.dispose();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(Get.reset);

  for (final fail in [false, true]) {
    testWidgets(
        'the sync icon stops spinning after a ${fail ? 'failed' : 'good'} sync',
        (tester) async {
      final lib = Get.put<LibraryPlaylistsController>(_FakeLibrary(fail))
          as _FakeLibrary;
      await tester.pumpWidget(GetMaterialApp(
        translations: Languages(),
        locale: const Locale('en'),
        home: const Scaffold(body: PipedSyncWidget(padding: EdgeInsets.zero)),
      ));
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pump();
      expect(lib.controller.isAnimating, isTrue);

      await tester.pump(const Duration(milliseconds: 20));
      // Was still repeating after a throw: nothing stopped it.
      expect(lib.controller.isAnimating, isFalse);
      expect(lib.controller.value, 0);
      await tester.pumpAndSettle();
    });
  }
}
