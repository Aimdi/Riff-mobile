import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';

class _FakeSettings extends GetxController implements SettingsScreenController {
  _FakeSettings(this.supportDirPath);
  @override
  final String supportDirPath;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What plays from the phone shows its cover: a downloaded song its saved
/// thumbnail; a downloaded episode or book chapter (no thumbnail saved) its
/// cover from the network, not the empty placeholder; a downloaded book's
/// chapter the cover kept with the book.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('art');
    Get.put<SettingsScreenController>(_FakeSettings(tmp.path));
  });
  tearDown(() {
    Get.reset();
    tmp.deleteSync(recursive: true);
  });

  /// [id] playing from its file on the phone (the player sets its url so).
  MediaItem fromPhone(String id, {Uri? art}) => MediaItem(
        id: id,
        title: 'Title',
        artUri: art ?? Uri.parse('https://example.com/$id.jpg'),
        extras: {'url': 'file:///data/downloads/$id.mp3'},
      );

  Future<void> show(WidgetTester tester, MediaItem song) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
          MaterialApp(home: Center(child: ImageWidget(song: song, size: 48))));
      // The file image tries its file (real I/O).
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  File imageFile(String path) => File(path)
    ..createSync(recursive: true)
    // A 1×1 PNG.
    ..writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='));

  /// The file the one image shows.
  String shownFile(WidgetTester tester) {
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final file = provider is ResizeImage ? provider.imageProvider : provider;
    return (file as FileImage).file.path;
  }

  testWidgets('an episode playing from the phone: its cover from the network',
      (tester) async {
    await show(tester, fromPhone('podcast_1'));
    final network =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(network.imageUrl, contains('example.com/podcast_1.jpg'));
  });

  testWidgets('a downloaded song: its saved thumbnail', (tester) async {
    imageFile('${tmp.path}/thumbnails/song1.png');
    await show(tester, fromPhone('song1'));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(shownFile(tester), '${tmp.path}/thumbnails/song1.png');
  });

  testWidgets('a downloaded book\'s chapter: the cover kept with the book',
      (tester) async {
    final cover = imageFile('${tmp.path}/audiobook_downloads/b/cover');
    await show(tester, fromPhone('abs_b_0', art: Uri.file(cover.path)));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(shownFile(tester), cover.path);
  });
}
