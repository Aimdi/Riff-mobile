import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/stats_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Stats/stats_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  List<MediaItem>? played;
  int? at;
  PlaylingFrom? from;

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    played = mediaItems;
    at = index;
    from = playfrom;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _top(String id, String title, {String kind = ''}) =>
    {'id': id, 'title': title, 'artist': 'Artist', 'plays': 1, 'kind': kind};

void main() {
  setUp(() async {
    for (final b in ['LIBFAV', 'LIBRP', 'SongStats', 'DailyStats']) {
      await Hive.openBox(b, bytes: Uint8List(0));
    }
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  test('top songs to play: kept ones as kept, music only, in order', () async {
    // As Riff keeps songs (YouTube Music's shape).
    Map<String, dynamic> kept(String id, String title, String album) => {
          'videoId': id,
          'title': title,
          'artists': [
            {'name': 'Artist'}
          ],
          'album': {'id': 'MPRE_$id', 'name': album},
          'thumbnails': [
            {'url': 'https://lh3.googleusercontent.com/$id'}
          ],
        };
    await Hive.box('LIBFAV').put('fav1', kept('fav1', 'Fav', 'The Album'));
    await Hive.box('LIBRP').add(kept('recent1', 'Recent', 'Recent LP'));

    final songs = topSongsToPlay([
      _top('fav1', 'Fav'),
      _top('podcast_ep', 'Episode', kind: 'podcast'),
      _top('new1', 'New'),
      _top('recent1', 'Recent'),
      _top('lv_1', 'Old chapter'),
    ]);
    expect(songs.map((m) => m.id), ['fav1', 'new1', 'recent1']);
    expect(songs[0].album, 'The Album');
    expect(songs[2].album, 'Recent LP');
    // Not kept anywhere: its title, artist and YouTube cover.
    expect(songs[1].title, 'New');
    expect(songs[1].artist, 'Artist');
    expect(songs[1].artUri.toString(),
        'https://i.ytimg.com/vi/new1/hqdefault.jpg');
  });

  testWidgets('Stats: a top song plays from there, Play from the top',
      (tester) async {
    await tester.runAsync(() async {
      final stats = Hive.box('SongStats');
      await stats.put('song1', {'title': 'First', 'artist': 'A', 'plays': 5});
      await stats.put('ep1', {
        'title': 'An episode',
        'artist': 'S',
        'plays': 4,
        'kind': 'podcast'
      });
      await stats.put('song2', {'title': 'Second', 'artist': 'B', 'plays': 3});
    });
    // Tall enough for every row to be built.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const StatsScreen(),
    ));

    await tester.tap(find.text('Second'));
    await tester.pump();
    expect(player.played?.map((m) => m.id), ['song1', 'song2']);
    expect(player.at, 1);
    // "Playing from" says your top songs, as Spotify's does.
    expect(player.from?.type, PlaylingFromType.SELECTION);
    expect(player.from?.nameString, 'topSongs');

    // An episode in the list doesn't play from here.
    player.played = null;
    await tester.tap(find.text('An episode'));
    await tester.pump();
    expect(player.played, isNull);

    await tester.tap(find.text('play'));
    await tester.pump();
    expect(player.at, 0);
  });
}
