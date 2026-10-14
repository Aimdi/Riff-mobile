import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/piped_service.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/widgets/create_playlist_dialog.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

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

  /// What Save / Rename asked for.
  (String, String?)? renamed;
  @override
  Future<bool> renamePlaylist(Playlist playlist, {String? description}) async {
    renamed = (textInputController.text, description);
    return true;
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

  testWidgets('with a larger font size, Cancel and Create & add stack',
      (tester) async {
    Get.put<LibraryPlaylistsController>(_FakeLibrary());
    Get.put<PipedServices>(_FakePiped());
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_app(Colors.green));
    // Not side by side off the dialog's edge.
    final cancel = tester.getRect(find.text('Cancel'));
    final create = tester.getRect(find.text('Create & add'));
    expect(create.top, greaterThanOrEqualTo(cancel.bottom));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(create.right, lessThanOrEqualTo(screen.width));
  });

  Widget editing(Playlist playlist) => GetMaterialApp(
        translations: Languages(),
        locale: const Locale('en'),
        home: Scaffold(
            body: CreateNRenamePlaylistPopup(
                renamePlaylist: true, playlist: playlist)),
      );

  testWidgets('Edit details: the name it has, its description, saved as typed',
      (tester) async {
    final lib =
        Get.put<LibraryPlaylistsController>(_FakeLibrary()) as _FakeLibrary;
    Get.put<PipedServices>(_FakePiped());
    await tester.pumpWidget(editing(Playlist(
        title: 'My EDM Mix',
        playlistId: 'LIB1',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        description: 'Library Playlist',
        isCloudPlaylist: false)));
    expect(find.text('Edit details'), findsOneWidget);
    // Starts from its name; its default words aren't its own.
    expect(lib.textInputController.text, 'My EDM Mix');
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Library Playlist'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'Late nights');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(lib.renamed, ('My EDM Mix', 'Late nights'));
  });

  testWidgets('a Piped playlist is only renamed', (tester) async {
    final lib =
        Get.put<LibraryPlaylistsController>(_FakeLibrary()) as _FakeLibrary;
    Get.put<PipedServices>(_FakePiped());
    await tester.pumpWidget(editing(Playlist(
        title: 'Shared',
        playlistId: 'PIPED1',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        description: 'Piped Playlist',
        isPipedPlaylist: true)));
    expect(find.text('Rename Playlist'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(lib.renamed, ('Shared', null));
  });

  test("a playlist's own words, not its kind's default", () {
    Playlist withWords(String? words) => Playlist(
        title: 'P', playlistId: 'P', thumbnailUrl: '', description: words);
    expect(withWords('Library Playlist').ownDescription, '');
    expect(withWords('Piped Playlist').ownDescription, '');
    expect(withWords(' Playlist ').ownDescription, '');
    expect(withWords(null).ownDescription, '');
    expect(withWords(' Late nights ').ownDescription, 'Late nights');
  });

  test('renamed as typed, with its description', () async {
    final box = await Hive.openBox('LibraryPlaylists', bytes: Uint8List(0));
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    addTearDown(Hive.close);
    final playlist = Playlist(
        title: 'old',
        playlistId: 'LIB1',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        description: 'Library Playlist',
        isCloudPlaylist: false);
    await box.put('LIB1', playlist.toJson());
    final library = LibraryPlaylistsController()
      ..textInputController.text = '  My EDM Mix ';
    expect(await library.renamePlaylist(playlist, description: ' Late nights '),
        isTrue);
    final saved = Playlist.fromJson(box.get('LIB1'));
    // It used to come out as "My edm mix".
    expect(saved.title, 'My EDM Mix');
    expect(saved.ownDescription, 'Late nights');
  });
}
