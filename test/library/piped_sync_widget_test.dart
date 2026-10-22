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
  _FakeLibrary(this.fail, {this.takes = const Duration(milliseconds: 10)});
  final bool fail;

  /// How long the sync takes.
  final Duration takes;

  @override
  late final AnimationController controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 5));

  @override
  Future<bool> syncPipedPlaylist() async {
    await Future<void>.delayed(takes);
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

Widget _app({bool reduce = false}) => GetMaterialApp(
      translations: Languages(),
      locale: const Locale('en'),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: const Scaffold(body: PipedSyncWidget(padding: EdgeInsets.zero)),
      ),
    );

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

  testWidgets('done, the icon finishes its half turn instead of snapping back',
      (tester) async {
    final lib = Get.put<LibraryPlaylistsController>(
        _FakeLibrary(false, takes: const Duration(seconds: 1))) as _FakeLibrary;
    await tester.pumpWidget(_app());
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump();
    for (var i = 0; i < 11; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Synced a fifth of a turn in: it carries on round, not back to 0.
    final turned = lib.controller.value;
    expect(turned, greaterThan(0));
    expect(lib.controller.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(lib.controller.value, greaterThan(turned));
    expect(lib.controller.value, lessThanOrEqualTo(0.5));

    await tester.pumpAndSettle();
    expect(lib.controller.isAnimating, isFalse);
    expect(lib.controller.value, 0);
  });

  testWidgets('Remove animations: no spinning', (tester) async {
    final lib = Get.put<LibraryPlaylistsController>(
        _FakeLibrary(false, takes: const Duration(seconds: 1))) as _FakeLibrary;
    await tester.pumpWidget(_app(reduce: true));
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump();
    expect(lib.controller.isAnimating, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(lib.controller.value, 0);
  });
}
