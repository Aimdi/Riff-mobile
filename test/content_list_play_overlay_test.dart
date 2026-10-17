import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/content_list_widget_item.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
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

  testWidgets('album rows grow with a larger font size rather than spill',
      (tester) async {
    const title = 'A rather long album title that runs onto a second line';
    Widget rows() => GetMaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(
            body: Column(
              children: [
                ListWidget(
                  [
                    Album(
                      title: title,
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
        );
    double rowHeight() => tester
        .getSize(find
            .ancestor(of: find.text(title), matching: find.byType(InkWell))
            .first)
        .height;

    await tester.pumpWidget(rows());
    expect(rowHeight(), RiffComponentSizes.wideRowExtent);

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(rows());
    expect(rowHeight(), greaterThan(RiffComponentSizes.wideRowExtent));
    // The cover keeps its size.
    expect(tester.getSize(find.byType(ImageWidget)).height,
        RiffComponentSizes.wideRowArt);
  });

  testWidgets('artist rows show a play overlay on the avatar', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ListWidget(
                [
                  Artist(
                    name: 'Ada',
                    browseId: 'UCtest',
                    thumbnailUrl: Playlist.thumbPlaceholderUrl,
                    subscribers: '1M',
                  ),
                ],
                'Artists',
                true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Ada'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });
}
