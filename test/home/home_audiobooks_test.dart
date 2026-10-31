import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/audiobook_catalog_service.dart';
import 'package:harmonymusic/services/free_audiobook_service.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_library_controller.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';
import 'package:harmonymusic/ui/screens/Home/home_metrics.dart';
import 'package:harmonymusic/ui/screens/Home/home_shelves.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

/// The saved books, without reading them from the phone.
class _Library extends AudiobookLibraryController {
  // Not the real one's: it reads the saved books from the phone.
  @override
  // ignore: must_call_super
  void onInit() {}
}

FreeAudiobook _free(String id, String title) =>
    FreeAudiobook(id: id, title: title, author: 'Herman Melville');

AudiobookItem _store(String id, String title) => AudiobookItem(
    id: id,
    title: title,
    author: 'Alexandre Dumas',
    cover: 'https://example.com/$id.jpg',
    genre: 'Classics',
    description: '');

void main() {
  late _Library lib;
  setUp(
      () => lib = Get.put<AudiobookLibraryController>(_Library()) as _Library);
  tearDown(Get.reset);

  test('your saved books: the free ones first, then store titles', () {
    lib.savedFree.assignAll([_free('moby_dick', 'Moby Dick')]);
    lib.saved.assignAll([_store('123', 'The Count of Monte Cristo')]);
    final shelf = yourAudiobooksShelf()!;
    expect(shelf.title, 'yourAudiobooks');
    expect(shelf.items.map((i) => i.key), ['book:moby_dick', 'book:store:123']);
  });

  test('none saved: no shelf', () {
    expect(yourAudiobooksShelf(), isNull);
  });

  test('a book you started stays in Jump back in only', () {
    lib.savedFree
        .assignAll([_free('moby_dick', 'Moby Dick'), _free('emma', 'Emma')]);
    final sections = buildHomeSections(HomeFeedInput(
      // Two tiles: the grid would drop a lone one to keep its rows even.
      jumpBackIn: [
        const HomeItem('book:moby_dick', 'Moby Dick'),
        const HomeItem('book:other', 'Other'),
      ],
      personalized: [yourAudiobooksShelf()!],
    ));
    final shelf = sections
        .firstWhere((m) => m.section == HomeSection.personalized)
        .shelves
        .single;
    expect(shelf.items.map((i) => i.key), ['book:emma']);
  });

  testWidgets('a book card shows its title and author', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: HomeShelfItem(
          value: _free('moby_dick', 'Moby Dick'),
          kind: HomeShelfKind.collections,
          metrics: const HomeMetrics(364),
        ),
      ),
    ));
    expect(find.text('Moby Dick'), findsOneWidget);
    expect(find.text('Herman Melville'), findsOneWidget);
  });
}
