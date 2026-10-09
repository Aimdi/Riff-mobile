import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/home_chip.dart';
import 'package:harmonymusic/models/home_shelf_content.dart';
import 'package:harmonymusic/models/quick_picks.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';

class _FakeHome extends GetxController implements HomeScreenController {
  @override
  final quickPicks = QuickPicks([]).obs;
  @override
  final middleContent = [].obs;
  @override
  final fixedContent = [].obs;
  @override
  final homeChips = <HomeChip>[].obs;
  @override
  ScrollController scrollControllerFor(String key) => ScrollController();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _song(String id, String title, String artist) => MediaItem(
    id: id,
    title: title,
    artist: artist,
    artUri: Uri.parse('https://lh3.googleusercontent.com/$id=w60-h60'));

void main() {
  tearDown(Get.reset);

  test('every YouTube shelf becomes one editorial shelf, in order', () {
    final home = Get.put<HomeScreenController>(_FakeHome()) as _FakeHome;
    home.middleContent.assignAll([
      SongContent(title: 'Listen again', songs: [
        _song('a', 'Song A (Remastered 2011)', 'Artist A, Guest'),
        _song('b', 'Song B', 'Artist B'),
      ]),
      'not a shelf',
    ]);
    home.fixedContent.assignAll([
      AlbumContent(title: 'Albums for you', albumList: [
        Album(
            title: 'X',
            browseId: 'MPREx',
            artists: const [
              {'name': 'Y'}
            ],
            thumbnailUrl: ''),
      ]),
    ]);

    final input = readHomeFeedInput(recent: const []);
    expect(input.editorial.map((s) => s.id),
        ['yt:Listen again', 'yt:Albums for you']);
    final songs = input.editorial.first.items;
    expect(songs.map((i) => i.key), ['song:a', 'song:b']);
    // The cross-source key drops bracketed extras and keeps the first
    // artist only.
    expect(songs.first.altKey, titleArtistKey('Song A', 'Artist A'));
    expect(songs.first.altKey, 'ta:song a|artist a');
    expect(input.editorial.last.items.single.key, 'album:MPREx');
  });
}
