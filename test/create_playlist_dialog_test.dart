import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/piped_service.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/widgets/create_playlist_dialog.dart';
import 'package:harmonymusic/utils/get_localization.dart';

class _FakeLibrary extends GetxController
    implements LibraryPlaylistsController {
  @override
  final textInputController = TextEditingController();
  @override
  final playlistCreationMode = "local".obs;
  @override
  final creationInProgress = false.obs;
  int modeResets = 0;
  @override
  void changeCreationMode(String? val) {
    modeResets++;
    playlistCreationMode.value = val!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePiped extends GetxService implements PipedServices {
  @override
  bool get isLoggedIn => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Color accent) => GetMaterialApp(
      translations: Languages(),
      locale: const Locale('en'),
      // A theme change rebuilds the dialog, as the album-colour theme does
      // on every new track.
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: accent)),
      home: const Scaffold(
          body: CreateNRenamePlaylistPopup(
              isCreateNadd: true,
              songItems: [MediaItem(id: 'a', title: 'Song A')])),
    );

void main() {
  tearDown(Get.reset);

  testWidgets('a theme change keeps the name being typed', (tester) async {
    final lib =
        Get.put<LibraryPlaylistsController>(_FakeLibrary()) as _FakeLibrary;
    Get.put<PipedServices>(_FakePiped());

    await tester.pumpWidget(_app(Colors.green));
    expect(lib.textInputController.text, 'Song A');
    expect(lib.modeResets, 1);

    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.pumpWidget(_app(Colors.purple));
    await tester.pumpAndSettle();

    // Was reset to the suggested name (and to local mode) on rebuild.
    expect(lib.textInputController.text, 'Road trip');
    expect(lib.modeResets, 1);
  });
}
