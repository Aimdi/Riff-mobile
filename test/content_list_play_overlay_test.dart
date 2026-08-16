import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/widgets/content_list_widget_item.dart';
import 'package:harmonymusic/ui/widgets/list_widget.dart';

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

  testWidgets('search album rows show a play overlay on the art',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ListWidget(
                [
                  Album(
                    title: 'LP',
                    browseId: 'MPREb_test',
                    artists: [
                      {'name': 'Artist'}
                    ],
                    year: '2024',
                    thumbnailUrl: Playlist.thumbPlaceholderUrl,
                  ),
                ],
                'Albums',
                true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('LP'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });
}
