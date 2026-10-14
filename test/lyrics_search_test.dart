import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/lyrics_search.dart';
import 'package:harmonymusic/services/synced_lyrics_service.dart';
import 'package:harmonymusic/ui/player/components/lyrics_search_sheet.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _song = MediaItem(
    id: 's1',
    title: 'Blinding Lights (feat. Someone) [Official Video]',
    artist: 'The Weeknd, Someone',
    duration: Duration(seconds: 200));

/// LRCLIB's answer to a search, as it sends it.
final _response = [
  {
    'trackName': 'Blinding Lights',
    'artistName': 'The Weeknd',
    'albumName': 'After Hours',
    'duration': 260.0,
    'instrumental': false,
    'plainLyrics': 'Long version',
    'syncedLyrics': '[00:01.00]Long version',
  },
  {
    'trackName': 'Blinding Lights',
    'artistName': 'The Weeknd',
    'duration': 199.5,
    'plainLyrics': 'Not synced',
    'syncedLyrics': null,
  },
  {
    'trackName': 'Blinding Lights',
    'artistName': 'The Weeknd',
    'albumName': 'After Hours',
    'duration': 201.0,
    'plainLyrics': 'I said, ooh',
    'syncedLyrics': '[00:10.00]I said, ooh',
  },
  {'trackName': 'Blinding Lights (Instrumental)', 'instrumental': true},
  {'trackName': 'Nothing in it', 'plainLyrics': '', 'syncedLyrics': ''},
  'not a result',
];

class _FakePlayer extends GetxController implements PlayerController {
  final picked = <Map<String, dynamic>>[];

  @override
  void useLyrics(MediaItem song, Map<String, dynamic> lyrics) =>
      picked.add(lyrics);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('synced lyrics first, then the nearest in length; none without lyrics',
      () {
    final found = lyricsCandidates(_response, 200);
    expect(found.map((c) => c.durationSec), [201, 260, 200]);
    expect(found.map((c) => c.isSynced), [true, true, false]);
    expect(found.first.album, 'After Hours');
    expect(lyricsCandidates({'error': 'bad'}, 200), isEmpty);
  });

  test('what to search: the title without the extras, and the first artist',
      () {
    expect(lyricsSearchQuery(_song), 'Blinding Lights The Weeknd');
    expect(
        lyricsSearchQuery(const MediaItem(
            id: 'x', title: 'Yesterday - Remastered 2009', artist: 'A & B')),
        'Yesterday A');
    // A live take's lyrics are the song's: kept as it's called.
    expect(
        lyricsSearchQuery(
            const MediaItem(id: 'y', title: 'Hello (Live)', artist: 'Adele')),
        'Hello (Live) Adele');
  });

  group('picked lyrics', () {
    setUp(() async {
      await Hive.openBox('lyrics', bytes: Uint8List(0));
      LyricsSearch.fetch = (_) async => _response;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    test('are the song\'s lyrics from then on', () async {
      final found = await LyricsSearch.search('blinding lights', _song);
      await LyricsSearch.choose(_song, found.first);
      final kept = await SyncedLyricsService.getSyncedLyrics(_song, 200);
      expect(kept?['synced'], '[00:10.00]I said, ooh');
      expect(kept?['plainLyrics'], 'I said, ooh');
      expect(kept?['chosen'], isTrue);
    });

    testWidgets('the sheet lists them; tapping one uses it', (tester) async {
      final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
      final asked = <String>[];
      LyricsSearch.fetch = (query) async {
        asked.add(query);
        return _response;
      };
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const LyricsSearchSheet(song: _song),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(asked, ['Blinding Lights The Weeknd']);
      // Labels show their keys: no translations loaded here.
      expect(find.text('lyricsSynced'), findsNWidgets(2));
      expect(find.text('lyricsPlain'), findsOneWidget);
      expect(find.text('The Weeknd · After Hours · 3:21'), findsOneWidget);

      await tester.tap(find.text('The Weeknd · After Hours · 3:21'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(player.picked.single['synced'], '[00:10.00]I said, ooh');
      expect(find.byType(LyricsSearchSheet), findsNothing);
    });
  });
}
