import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/widgets/confirm_dialog.dart';
import 'package:harmonymusic/ui/widgets/songinfo_bottom_sheet.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

class _Remover with RemoveSongFromPlaylistMixin {}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

void main() {
  group('remove from a local playlist, then undo', () {
    late Directory tmp;
    final playlist = Playlist(
      title: 'Road trip',
      playlistId: 'LIBRP_road',
      thumbnailUrl: '',
      isCloudPlaylist: false,
    );

    setUp(() async {
      Get.reset();
      tmp = await Directory.systemTemp.createTemp('playlist_undo');
      Hive.init(p.join(tmp.path, 'hive'));
      final box = await Hive.openBox(playlist.playlistId);
      await box.putAll({
        for (final (i, id) in ['a', 'b', 'c'].indexed)
          i: MediaItemBuilder.toJson(_song(id)),
      });
    });
    tearDown(() async {
      Get.reset();
      await Hive.deleteFromDisk();
      tmp.deleteSync(recursive: true);
    });

    List<String> ids() => Hive.box(playlist.playlistId)
        .values
        .map((v) => (v as Map)['videoId'] as String)
        .toList();

    test('reports where the song was and puts it back there', () async {
      final remover = _Remover();
      int? at;
      final ok = await remover.removeSongFromPlaylist(_song('b'), playlist,
          onRemovedAt: (i) => at = i);
      expect(ok, isTrue);
      expect(at, 1);
      expect(ids(), ['a', 'c']);

      await remover.restoreSongToPlaylist(_song('b'), playlist, at!);
      expect(ids(), ['a', 'b', 'c']);
    });

    test('undo twice does not duplicate the song', () async {
      final remover = _Remover();
      await remover.removeSongFromPlaylist(_song('a'), playlist);
      await remover.restoreSongToPlaylist(_song('a'), playlist, 0);
      await remover.restoreSongToPlaylist(_song('a'), playlist, 0);
      expect(ids(), ['a', 'b', 'c']);
    });

    test('a position past the end lands at the end', () async {
      final remover = _Remover();
      await remover.removeSongFromPlaylist(_song('c'), playlist);
      await remover.restoreSongToPlaylist(_song('c'), playlist, 99);
      expect(ids(), ['a', 'b', 'c']);
    });
  });

  group('confirmDestructive', () {
    Future<bool?> ask(WidgetTester tester, String tap) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async => result = await confirmDestructive(c,
                  title: 'Delete playlist?',
                  message: 'Gone for good.',
                  confirmLabel: 'Delete'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete playlist?'), findsOneWidget);
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('Delete confirms', (tester) async {
      expect(await ask(tester, 'Delete'), isTrue);
    });

    testWidgets('Cancel does not', (tester) async {
      // No translations loaded: the cancel label is its key.
      expect(await ask(tester, 'cancel'), isFalse);
    });
  });
}
