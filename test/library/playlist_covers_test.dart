import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/folder_cover.dart';
import 'package:harmonymusic/services/playlist_covers.dart';
import 'package:harmonymusic/ui/widgets/generated_cover.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(30, 185, 84));
  return Uint8List.fromList(img.encodePng(im));
}

Playlist _pl(String id) => Playlist(
      title: 'Road trip',
      playlistId: id,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    );

/// An [Image] showing the file at [path] (Image.file wraps it in a
/// [ResizeImage] when it is given a decode size).
Finder _photo(String path) => find.byWidgetPredicate((w) {
      if (w is! Image) return false;
      var provider = w.image;
      if (provider is ResizeImage) provider = provider.imageProvider;
      return provider is FileImage && provider.file.path == path;
    });

void main() {
  group('PlaylistCovers', () {
    late Directory tmp;
    late Future<String> Function() realBase;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_playlist_cover_');
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      realBase = FolderCoverStore.baseDir;
      FolderCoverStore.baseDir = () async => tmp.path;
    });
    tearDown(() async {
      FolderCoverStore.baseDir = realBase;
      await Hive.box('AppPrefs').close();
      await tmp.delete(recursive: true);
    });

    test('a square JPEG under playlist_covers; a new one replaces it',
        () async {
      expect(PlaylistCovers.pathFor('LIB1'), isNull);
      expect(await PlaylistCovers.set('LIB1', _png(1200, 800)), isTrue);
      final first = PlaylistCovers.pathFor('LIB1')!;
      expect(first, startsWith('${tmp.path}/playlist_covers/LIB1_'));
      final back = img.decodeJpg(File(first).readAsBytesSync())!;
      expect(back.width, kFolderCoverSide);
      expect(back.height, kFolderCoverSide);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(await PlaylistCovers.set('LIB1', _png(50, 50)), isTrue);
      final second = PlaylistCovers.pathFor('LIB1')!;
      expect(second, isNot(first));
      expect(File(first).existsSync(), isFalse);
      expect(File(second).existsSync(), isTrue);

      final rev = PlaylistCovers.rev.value;
      await PlaylistCovers.remove('LIB1');
      expect(PlaylistCovers.pathFor('LIB1'), isNull);
      expect(File(second).existsSync(), isFalse);
      expect(PlaylistCovers.rev.value, rev + 1);
    });

    test('not an image: nothing changes', () async {
      final rev = PlaylistCovers.rev.value;
      expect(await PlaylistCovers.set('LIB1', Uint8List.fromList([1, 2, 3])),
          isFalse);
      expect(PlaylistCovers.pathFor('LIB1'), isNull);
      await PlaylistCovers.remove('LIB1');
      expect(PlaylistCovers.rev.value, rev);
    });

    test('an id that is no file name still gets a file', () async {
      expect(await PlaylistCovers.set('a/b:c', _png(40, 40)), isTrue);
      final path = PlaylistCovers.pathFor('a/b:c')!;
      expect(path, startsWith('${tmp.path}/playlist_covers/a_b_c_'));
      expect(File(path).existsSync(), isTrue);
    });
  });

  group('ImageWidget', () {
    const path = '/does/not/matter.jpg';
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      await Hive.box('AppPrefs').put(PlaylistCovers.key, {'LIB1': path});
    });
    tearDown(() async {
      await Hive.box('AppPrefs').close();
    });

    Widget host(Playlist playlist) => MaterialApp(
          home: Center(child: ImageWidget(playlist: playlist, size: 120)),
        );

    testWidgets("a playlist's photo wins over its cover, as soon as it's set",
        (tester) async {
      await tester.pumpWidget(host(_pl('LIB1')));
      expect(_photo(path), findsOneWidget);
      expect(find.byType(GeneratedCover), findsNothing);

      await PlaylistCovers.remove('LIB1');
      await tester.pump();
      expect(_photo(path), findsNothing);
      expect(find.byType(GeneratedCover), findsOneWidget);
    });

    testWidgets('other playlists keep their own cover', (tester) async {
      await tester.pumpWidget(host(_pl('LIB2')));
      expect(find.byType(Image), findsNothing);
      expect(find.byType(GeneratedCover), findsOneWidget);
    });
  });
}
