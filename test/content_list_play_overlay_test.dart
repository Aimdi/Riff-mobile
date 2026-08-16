import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/widgets/content_list_widget_item.dart';

void main() {
  testWidgets('shelf card keeps title tap target and shows play overlay',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: ContentListItem(
            content: Playlist(
              title: 'Favorites',
              playlistId: 'LIBFAV',
              thumbnailUrl: Playlist.thumbPlaceholderUrl,
              isCloudPlaylist: false,
            ),
            isLibraryItem: true,
          ),
        ),
      ),
    );

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });
}
