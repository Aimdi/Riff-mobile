import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/search_recents.dart';
import 'package:harmonymusic/ui/screens/Search/components/search_recent_row.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/content_list_widget_item.dart';
import 'package:hive/hive.dart';

MediaItem _song(String id, {String artist = 'Daft Punk'}) => MediaItem(
      id: id,
      title: 'Song $id',
      artist: artist,
      artUri: Uri.parse('https://lh3.googleusercontent.com/$id'),
      extras: {
        'artists': [
          {'name': artist, 'id': 'UC1'},
        ],
      },
    );

final _artist = Artist(
    name: 'Daft Punk',
    browseId: 'UCartist',
    thumbnailUrl: 'https://lh3.googleusercontent.com/a');
final _album = Album(
    title: 'Discovery',
    browseId: 'MPREb_album',
    artists: [
      {'name': 'Daft Punk', 'id': 'UCartist'},
    ],
    year: '2001',
    thumbnailUrl: 'https://lh3.googleusercontent.com/b');
final _playlist = Playlist(
    title: 'French house',
    playlistId: 'PLfrench',
    thumbnailUrl: 'https://lh3.googleusercontent.com/c');
final _podcast = Playlist(
    title: 'Song Exploder',
    playlistId: 'MPSPpodcast',
    thumbnailUrl: 'https://lh3.googleusercontent.com/d');

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    SearchRecents.rev.value = 0;
  });
  tearDown(() => Hive.box('AppPrefs').close());

  List<String> ids() => [for (final r in SearchRecents.items) r.id];

  test('newest first, once each, and no more than ten', () async {
    await SearchRecents.note(_song('a'));
    await SearchRecents.note(_artist);
    await SearchRecents.note(_song('a'));
    expect(ids(), ['a', 'UCartist']);
    expect(SearchRecents.rev.value, 3);

    for (var i = 0; i < 12; i++) {
      await SearchRecents.note(_song('s$i'));
    }
    expect(ids(), hasLength(SearchRecents.max));
    expect(ids().first, 's11');
  });

  test('each kind comes back as it was', () async {
    for (final item in [_song('a'), _artist, _album, _playlist, _podcast]) {
      await SearchRecents.note(item);
    }
    final items = SearchRecents.items;
    expect([
      for (final r in items) r.kind
    ], [
      SearchRecentKind.playlist,
      SearchRecentKind.playlist,
      SearchRecentKind.album,
      SearchRecentKind.artist,
      SearchRecentKind.song,
    ]);
    final song = items.last.item as MediaItem;
    expect(song.title, 'Song a');
    expect(song.artist, 'Daft Punk');
    expect('${song.artUri}', startsWith('https://lh3.googleusercontent.com/a'));
    expect((items[2].item as Album).year, '2001');
    expect((items[3].item as Artist).name, 'Daft Punk');
    expect((items[0].item as Playlist).playlistId, 'MPSPpodcast');

    // What it says each is.
    expect(items.map(searchRecentSubtitle), [
      'podcastKind',
      'playlist',
      'album · Daft Punk',
      'artist',
      'songKind · Daft Punk',
    ]);
  });

  test('one forgotten, then all', () async {
    await SearchRecents.note(_song('a'));
    await SearchRecents.note(_album);
    await SearchRecents.remove(SearchRecents.items.first);
    expect(ids(), ['a']);
    await SearchRecents.clear();
    expect(SearchRecents.items, isEmpty);
  });

  test("what isn't a search result, or can't be read, is left out", () async {
    await SearchRecents.note('a query');
    expect(SearchRecents.items, isEmpty);
    await Hive.box('AppPrefs').put(SearchRecents.key, [
      {'kind': 'song', 'item': 'junk'},
      {'kind': 'nonsense', 'item': <String, dynamic>{}},
      'junk',
      SearchRecent.of(_artist)!.toJson(),
    ]);
    expect(ids(), ['UCartist']);
  });

  testWidgets('only what is opened from the search results is kept',
      (tester) async {
    late BuildContext inResults;
    late BuildContext elsewhere;
    await tester.pumpWidget(Column(children: [
      SearchRecentsScope(child: Builder(builder: (c) {
        inResults = c;
        return const SizedBox();
      })),
      Builder(builder: (c) {
        elsewhere = c;
        return const SizedBox();
      }),
    ]));
    await tester.runAsync(() async {
      noteSearchOpen(elsewhere, _album);
      noteSearchOpen(inResults, _artist);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(ids(), ['UCartist']);
  });

  testWidgets('a recent search row: what it is, and ✕ forgets it',
      (tester) async {
    // No cover to fetch in a test.
    await tester.runAsync(() => SearchRecents.note(Album(
        title: 'Discovery',
        browseId: 'MPREb_album',
        artists: [
          {'name': 'Daft Punk'},
        ],
        thumbnailUrl: '')));
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: SearchRecentRow(recent: SearchRecents.items.single),
      ),
    ));
    expect(find.text('Discovery'), findsOneWidget);
    expect(find.text('album · Daft Punk'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.close_rounded));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(SearchRecents.items, isEmpty);
  });

  testWidgets('a playlist opened from the search results is kept',
      (tester) async {
    final opened = <String?>[];
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Navigator(
          key: Get.nestedKey(ScreenNavigationSetup.id),
          onGenerateRoute: (settings) {
            if (settings.name != '/') opened.add(settings.name);
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => settings.name == '/'
                  ? SearchRecentsScope(
                      child: ContentListItem(
                        content: Playlist(
                            title: 'French house',
                            playlistId: 'PLfrench',
                            thumbnailUrl: Playlist.thumbPlaceholderUrl),
                      ),
                    )
                  : const SizedBox(),
            );
          },
        ),
      ),
    ));
    await tester.runAsync(() async {
      // Its name under the cover (the generated cover shows it too).
      await tester.tap(find.text('French house').last);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(opened, [ScreenNavigationSetup.playlistScreen]);
    expect(ids(), ['PLfrench']);
  });
}
