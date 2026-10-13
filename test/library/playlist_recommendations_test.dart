import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Playlist/playlist_recommendations.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Song $id', artist: 'Artist $id');

List<String> _ids(List<MediaItem> songs) => [for (final s in songs) s.id];

void main() {
  group('recommendationSeeds', () {
    final ten = [for (var i = 0; i < 10; i++) _song('p$i')];

    test('the latest added first, then others spread over the playlist', () {
      expect(_ids(recommendationSeeds(ten)), ['p9', 'p6', 'p3']);
    });

    test('each refresh starts one song further back', () {
      expect(_ids(recommendationSeeds(ten, round: 1)), ['p8', 'p5', 'p2']);
      expect(_ids(recommendationSeeds(ten, round: 10)), ['p9', 'p6', 'p3']);
    });

    test('short playlists: each song once', () {
      expect(_ids(recommendationSeeds([_song('a')])), ['a']);
      expect(_ids(recommendationSeeds([_song('a'), _song('b')])), ['b', 'a']);
      expect(recommendationSeeds(const []), isEmpty);
    });
  });

  group('pickPlaylistRecommendations', () {
    test('every seed in turn, up to the limit', () {
      final picked = pickPlaylistRecommendations([
        [_song('a1'), _song('a2'), _song('a3')],
        [_song('b1'), _song('b2')],
        [_song('c1')],
      ], exclude: {}, limit: 4);
      expect(_ids(picked), ['a1', 'b1', 'c1', 'a2']);
    });

    test("each once, none from the playlist, none that's banned", () {
      final picked = pickPlaylistRecommendations([
        [_song('in'), _song('x'), _song('banned')],
        [_song('x'), _song('y')],
      ], exclude: {
        'in'
      }, blocked: (s) => s.id == 'banned');
      expect(_ids(picked), ['x', 'y']);
    });
  });

  group('PlaylistRecommendations', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ));
    }

    testWidgets('songs like the playlist, without its own; + adds one',
        (tester) async {
      final added = <String>[];
      await pump(
        tester,
        PlaylistRecommendations(
          songs: [_song('p1'), _song('p2')],
          playlistTitle: 'Road trip',
          onAdd: (s) async {
            added.add(s.id);
            return true;
          },
          load: (seed) async => [_song('p1'), _song('r1'), _song('r2')],
        ),
      );
      // Loading.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();
      expect(find.text('recommendedSongs'), findsOneWidget);
      expect(find.text('Song r1'), findsOneWidget);
      expect(find.text('Song r2'), findsOneWidget);
      expect(find.text('Song p1'), findsNothing);

      await tester.tap(find.byTooltip('addToThisPlaylist').first);
      await tester.pump();
      expect(added, ['r1']);
      expect(find.text('Song r1'), findsNothing);
      expect(find.text('Song r2'), findsOneWidget);
      expect(find.text('addedToThisPlaylist'), findsOneWidget);
    });

    testWidgets('refresh brings others, from other songs of the playlist',
        (tester) async {
      final seeds = <String>[];
      await pump(
        tester,
        PlaylistRecommendations(
          songs: [for (var i = 0; i < 10; i++) _song('p$i')],
          playlistTitle: 'Road trip',
          onAdd: (_) async => true,
          load: (seed) async {
            seeds.add(seed.id);
            return [for (var i = 0; i < 5; i++) _song('${seed.id}-r$i')];
          },
        ),
      );
      await tester.pump();
      expect(seeds, ['p9', 'p6', 'p3']);
      expect(find.text('Song p9-r0'), findsOneWidget);

      await tester.tap(find.byTooltip('refreshRecommendations'));
      await tester.pump();
      await tester.pump();
      expect(seeds, ['p9', 'p6', 'p3', 'p8', 'p5', 'p2']);
      expect(find.text('Song p9-r0'), findsNothing);
      expect(find.text('Song p8-r0'), findsOneWidget);
    });

    testWidgets('nothing at all when there are none (offline)', (tester) async {
      await pump(
        tester,
        PlaylistRecommendations(
          songs: [_song('p1')],
          playlistTitle: 'Road trip',
          onAdd: (_) async => true,
          load: (seed) async => throw Exception('offline'),
        ),
      );
      await tester.pump();
      expect(find.text('recommendedSongs'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
