import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/audiobook_progress_service.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';
import 'package:harmonymusic/ui/screens/Home/home_jump_back_in.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

Map<String, dynamic> _record(String id, String bookId, int at) => {
      'id': id,
      'bookId': bookId,
      'title': 'Chapter $id',
      'album': 'Book $bookId',
      'positionMs': 600000,
      'durationMs': 1800000,
      'updatedAt': at,
    };

Box get _box => Hive.box(AudiobookProgressService.boxName);

void main() {
  setUp(() async {
    await Hive.openBox(AudiobookProgressService.boxName, bytes: Uint8List(0));
    await _box.putAll({
      'lv_b1_1': _record('lv_b1_1', 'b1', 1),
      'lv_b1_2': _record('lv_b1_2', 'b1', 2),
      'lv_b2_1': _record('lv_b2_1', 'b2', 3),
    });
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  test("a book's place forgotten, all its chapters, and put back", () async {
    final taken = await AudiobookProgressService.forgetBook('b1');
    expect(taken.map((r) => r['id']), unorderedEquals(['lv_b1_1', 'lv_b1_2']));
    expect(_box.keys, ['lv_b2_1']);
    expect(
        AudiobookProgressService.latestPerBook(
                AudiobookProgressService.inProgress())
            .map((r) => r['bookId']),
        ['b2']);

    await AudiobookProgressService.restore(taken);
    expect(_box.keys, unorderedEquals(['lv_b1_1', 'lv_b1_2', 'lv_b2_1']));
    expect(AudiobookProgressService.positionMs('lv_b1_2'), 600000);
  });

  testWidgets("Jump back in: a book's menu marks it finished, with Undo",
      (tester) async {
    final book = HomeResumable(
      kind: ResumeKind.book,
      id: 'b1',
      title: 'Book b1',
      progress: 0.3,
      record: _record('lv_b1_2', 'b1', 2),
    );
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 300, child: JumpBackInTile(item: book)),
        ),
      ),
    ));
    final rev = homeFeedRev.value;

    await tester.longPress(find.byType(JumpBackInTile));
    await tester.pumpAndSettle();
    expect(find.text('markAsFinished'), findsOneWidget);

    await tester.tap(find.text('markAsFinished'));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_box.keys, ['lv_b2_1']);
    expect(homeFeedRev.value, greaterThan(rev));
    expect(find.text('markedAsFinished'), findsOneWidget);

    await tester.tap(find.text('undo'));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(_box.keys, unorderedEquals(['lv_b1_1', 'lv_b1_2', 'lv_b2_1']));
    await tester.pumpAndSettle();
  });
}
