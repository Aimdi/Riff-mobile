import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/audiobook_bookmarks.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_bookmarks_ui.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

/// Track [i] of an Audiobookshelf book.
MediaItem _track(int i) => MediaItem(
      id: 'abs_book1_$i',
      title: 'Chapter ${i + 1}',
      album: 'The Book',
      artist: 'Author',
      extras: const {'absItemId': 'book1'},
    );

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentQueue = [for (var i = 0; i < 3; i++) _track(i)].obs;
  @override
  final currentSong = Rxn<MediaItem>(_track(1));
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero,
          current: const Duration(minutes: 5),
          total: const Duration(minutes: 30))
      .obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  final opened = <(int, Duration)>[];

  @override
  void playQueueItemAt(int index, Duration position) =>
      opened.add((index, position));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await Hive.openBox(AudiobookBookmarkStore.box, bytes: Uint8List(0));
  });
  tearDown(() async {
    Get.reset();
    await Hive.box(AudiobookBookmarkStore.box).close();
  });

  test('kept per book, in reading order', () async {
    await AudiobookBookmarkStore.add(_track(2), const Duration(seconds: 10),
        trackIndex: 2);
    await AudiobookBookmarkStore.add(_track(0), const Duration(minutes: 9),
        trackIndex: 0);
    await AudiobookBookmarkStore.add(_track(0), const Duration(minutes: 1),
        trackIndex: 0);
    final book = AudiobookBookmarkStore.forBook('book1');
    expect([for (final b in book) (b.trackIndex, b.positionMs ~/ 1000)],
        [(0, 60), (0, 540), (2, 10)]);
    expect(book.first.trackId, 'abs_book1_0');
    expect(book.first.trackTitle, 'Chapter 1');

    // A free (LibriVox) book is a book too; a song isn't.
    final free = await AudiobookBookmarkStore.add(
        const MediaItem(
            id: 'lv_42_3', title: 'Part 4', extras: {'audiobookId': 'lv42'}),
        const Duration(seconds: 5),
        trackIndex: 3);
    expect(free?.bookId, 'lv42');
    expect(
        await AudiobookBookmarkStore.add(
            const MediaItem(id: 'song', title: 'Song'), Duration.zero,
            trackIndex: 0),
        isNull);
    expect(AudiobookBookmarkStore.forBook('book1'), hasLength(3));
  });

  group('in the player', () {
    late _FakePlayer player;
    setUp(
        () => player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer);

    Future<void> pumpPlayer(WidgetTester tester) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(
            key: player.homeScaffoldkey,
            body: Builder(
              builder: (context) => TextButton(
                // The player's ⋮ sheet.
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const AudiobookBookmarkTiles(),
                ),
                child: const Text('menu'),
              ),
            ),
          ),
        ));

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
    }

    testWidgets('bookmark the moment, then play from it', (tester) async {
      await pumpPlayer(tester);
      await openMenu(tester);
      await tester.tap(find.text('bookmarkThisMoment'));
      await tester.pumpAndSettle();
      final saved = AudiobookBookmarkStore.forBook('book1');
      expect(saved.single.trackIndex, 1);
      expect(
          saved.single.positionMs, const Duration(minutes: 5).inMilliseconds);
      expect(find.text('bookmarkSaved'), findsOneWidget);

      await openMenu(tester);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('bookBookmarks'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 2'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AudiobookBookmarkTile),
              matching: find.text('5:00')),
          findsOneWidget);

      await tester.tap(find.text('Chapter 2'));
      await tester.pumpAndSettle();
      expect(player.opened, [(1, const Duration(minutes: 5))]);
    });

    testWidgets('remove one, then Undo', (tester) async {
      await tester.runAsync(() => AudiobookBookmarkStore.add(
          _track(0), const Duration(seconds: 42),
          trackIndex: 0));
      await pumpPlayer(tester);
      await openMenu(tester);
      await tester.tap(find.text('bookBookmarks'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1'), findsOneWidget);
      expect(find.text('0:42'), findsOneWidget);

      await tester.tap(find.byTooltip('bookmarkRemove'));
      await tester.pumpAndSettle();
      expect(find.text('noBookBookmarks'), findsOneWidget);
      expect(AudiobookBookmarkStore.forBook('book1'), isEmpty);

      await tester.tap(find.text('undo'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1'), findsOneWidget);
    });

    testWidgets('nothing for music', (tester) async {
      player.currentSong.value = const MediaItem(id: 'song', title: 'Song');
      await pumpPlayer(tester);
      await openMenu(tester);
      expect(find.text('bookmarkThisMoment'), findsNothing);
    });
  });
}
