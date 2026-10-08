import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/folder_cover.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_folder_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_folder_cover.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(200, 40, 90));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  group('processFolderCover', () {
    test('a big landscape photo becomes a 640 px square JPEG', () {
      final out = processFolderCover(_png(1200, 800))!;
      expect(out.sublist(0, 2), [0xFF, 0xD8]); // JPEG magic
      final back = img.decodeJpg(out)!;
      expect(back.width, kFolderCoverSide);
      expect(back.height, kFolderCoverSide);
    });

    test('a small portrait photo is cropped square, never enlarged', () {
      final back = img.decodeJpg(processFolderCover(_png(300, 500))!)!;
      expect(back.width, 300);
      expect(back.height, 300);
    });

    test('anything that is not an image is null', () {
      expect(processFolderCover(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  test('the photo survives a save and load, and old folders have none', () {
    final f = PodcastFolder('1', 'News', ['PLx'],
        colorIndex: 2, imagePath: '/x/1_5.jpg');
    final back = PodcastFolder.fromMap(f.toMap());
    expect(back.imagePath, '/x/1_5.jpg');
    expect(back.colorIndex, 2);
    expect(PodcastFolder('2', 'Old', []).toMap().containsKey('image'), isFalse);
    expect(
        PodcastFolder.fromMap({'id': '3', 'name': 'x', 'image': ''}).imagePath,
        isNull);
  });

  group('store and controller', () {
    late Directory tmp;
    late Future<String> Function() realBase;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_folder_cover_');
      Hive.init(tmp.path);
      await Hive.openBox('PodcastFolders');
      realBase = FolderCoverStore.baseDir;
      FolderCoverStore.baseDir = () async => tmp.path;
    });
    tearDown(() async {
      FolderCoverStore.baseDir = realBase;
      Get.reset();
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('save writes a square JPEG under folder_covers', () async {
      final path = (await FolderCoverStore.save('f1', _png(900, 700)))!;
      expect(path, startsWith('${tmp.path}/folder_covers/f1_'));
      final back = img.decodeJpg(File(path).readAsBytesSync())!;
      expect(back.width, kFolderCoverSide);
      expect(back.height, kFolderCoverSide);
      expect(await FolderCoverStore.save('f1', Uint8List(8)), isNull);
    });

    test('a new photo or deleting the folder removes the old file', () async {
      final fc = Get.put(PodcastFolderController());
      final folder = fc.createFolder('Tech');
      final first = (await FolderCoverStore.save(folder.id, _png(50, 50)))!;
      fc.setImage(folder.id, first);
      expect(fc.findById(folder.id)!.imagePath, first);
      final stored = (Hive.box('PodcastFolders').get('folders') as List).first;
      expect((stored as Map)['image'], first);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = (await FolderCoverStore.save(folder.id, _png(60, 60)))!;
      fc.setImage(folder.id, second);
      expect(File(first).existsSync(), isFalse);
      expect(File(second).existsSync(), isTrue);

      fc.setImage(folder.id, null);
      expect(File(second).existsSync(), isFalse);
      expect(fc.findById(folder.id)!.imagePath, isNull);

      final third = (await FolderCoverStore.save(folder.id, _png(60, 60)))!;
      fc.setImage(folder.id, third);
      fc.deleteFolder(folder.id);
      expect(File(third).existsSync(), isFalse);

      // A photo for a folder that is gone is not kept.
      final orphan = (await FolderCoverStore.save('nope', _png(40, 40)))!;
      fc.setImage('nope', orphan);
      expect(File(orphan).existsSync(), isFalse);
    });
  });

  group('PodcastFolderCover', () {
    Widget host(PodcastFolder f) => MaterialApp(
          home: Center(
            child: SizedBox.square(
                dimension: 160, child: PodcastFolderCover(folder: f)),
          ),
        );

    testWidgets('no photo: the tinted folder icon', (tester) async {
      await tester.pumpWidget(host(PodcastFolder('1', 'A', [])));
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('photo: framed in the folder colour', (tester) async {
      final f = PodcastFolder('1', 'A', [],
          colorIndex: 3, imagePath: '/does/not/matter.jpg');
      await tester.pumpWidget(host(f));
      expect(find.byType(Image), findsOneWidget);
      final frame = tester.widget<ColoredBox>(find
          .ancestor(
              of: find.byType(ClipRRect), matching: find.byType(ColoredBox))
          .first);
      expect(frame.color, f.color);
    });
  });
}
