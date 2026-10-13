import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/library_view_mode.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/content_list_widget_item.dart';
import 'package:hive/hive.dart';

void main() {
  test('list or grid, kept', () async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    addTearDown(() => Hive.box('AppPrefs').close());
    expect(LibraryViewMode.list.value, isFalse);

    await LibraryViewMode.setList(true);
    expect(LibraryViewMode.list.value, isTrue);
    expect(Hive.box('AppPrefs').get(LibraryViewMode.prefKey), isTrue);

    await LibraryViewMode.setList(false);
    expect(Hive.box('AppPrefs').get(LibraryViewMode.prefKey), isFalse);
  });

  Future<void> pumpRow(WidgetTester tester, Object content) =>
      tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(
          body: ListView(
            children: [
              ContentListItem(
                content: content,
                isLibraryItem: true,
                size: RiffComponentSizes.rowArt,
                asRow: true,
              ),
            ],
          ),
        ),
      ));

  testWidgets('a playlist row: cover, name and count, no play button',
      (tester) async {
    await pumpRow(
        tester,
        Playlist(
          title: 'Road trip',
          playlistId: 'PLroad',
          thumbnailUrl: Playlist.thumbPlaceholderUrl,
          songCount: '12',
          isCloudPlaylist: false,
        ));
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('12 songs'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
    // A row, the cover at the row size.
    final row = tester.getSize(find.byType(ContentListItem));
    expect(row.width, greaterThan(row.height));
    expect(row.height, greaterThanOrEqualTo(RiffComponentSizes.rowArt));
  });

  testWidgets('an album row: artist and year', (tester) async {
    await pumpRow(
        tester,
        Album(
          title: 'LP',
          browseId: 'MPREb_test',
          artists: [
            {'name': 'Artist'}
          ],
          year: '2024',
          thumbnailUrl: Playlist.thumbPlaceholderUrl,
        ));
    expect(find.text('LP'), findsOneWidget);
    expect(find.text('Artist • 2024'), findsOneWidget);
  });

  testWidgets('a system playlist row keeps its icon cover', (tester) async {
    await pumpRow(
        tester,
        Playlist(
          title: 'Favorites',
          playlistId: 'LIBFAV',
          thumbnailUrl: Playlist.thumbPlaceholderUrl,
          isCloudPlaylist: false,
        ));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });
}
