import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Library/library_search.dart';
import 'package:harmonymusic/ui/screens/Search/search_result_screen.dart'
    show Body;
import 'package:harmonymusic/ui/screens/Search/search_result_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

import '../fakes/fake_music_services.dart';

/// Your library's songs: downloads and the song cache, the phone's songs.
class _FakeLibrary extends GetxController implements LibrarySongsController {
  @override
  late RxList<MediaItem> librarySongsList = <MediaItem>[].obs;
  @override
  final deviceSongs = <MediaItem>[].obs;
  @override
  List<MediaItem> tempListContainer = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  final isCurrentSongFav = false.obs;
  @override
  final buttonState = PlayButtonState.paused.obs;

  List<MediaItem>? playedList;
  int? playedIndex;
  PlaylingFrom? playedFrom;

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    playedList = mediaItems;
    playedIndex = index;
    playedFrom = playfrom;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = false.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _song(String id, String title, String artist) =>
    MediaItem(id: id, title: title, artist: artist);

void main() {
  late FakeMusicServices music;
  late SearchResultScreenController c;

  setUp(() {
    music = FakeMusicServices();
    Get.put<MusicServices>(music);
    // Not put: no onReady, so no search until asked.
    c = SearchResultScreenController();
    c.queryString.value = 'daft punk';
  });
  tearDown(() async {
    Get.reset();
    await OfflinePlayback.resetForTest();
  });

  test('a search that fails is told apart from one that finds nothing',
      () async {
    music.error = Exception('offline');
    await c.retrySearch();
    expect(c.searchFailed.value, isTrue);
    expect(c.isResultContentFetced.value, isTrue);
    expect(c.railItems, isEmpty);

    // Tried again: loading, then the results.
    music.error = null;
    final again = c.retrySearch();
    expect(c.searchFailed.value, isFalse);
    expect(c.isResultContentFetced.value, isFalse);
    music.searches[null]!.single.complete({
      'Songs': ['song']
    });
    await again;
    expect(c.searchFailed.value, isFalse);
    expect(c.railItems, ['Songs']);
    expect(music.searches[null], hasLength(1));
  });

  group('the page', () {
    Future<void> pumpBody(WidgetTester tester) => tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(body: Body(searchResScrController: c)),
        ));

    testWidgets('a failed search says so and tries again; no match as before',
        (tester) async {
      c.searchFailed.value = true;
      c.isResultContentFetced.value = true;
      await pumpBody(tester);
      // Labels show their keys: no translations loaded here.
      expect(find.text('searchFailed'), findsOneWidget);
      expect(find.text('nomatch\n\'daft punk\''), findsNothing);

      await tester.tap(find.text('retry'));
      await tester.pump();
      music.searches[null]!.single.complete({});
      await tester.pump();
      expect(find.text('searchFailed'), findsNothing);
      expect(find.text('nomatch\n\'daft punk\''), findsOneWidget);
    });

    testWidgets(
        'offline, what your library has for it is there to play, '
        'as Spotify and YouTube Music search your downloads', (tester) async {
      final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
      Get.put<SettingsScreenController>(_FakeSettings());
      final library =
          Get.put<LibrarySongsController>(_FakeLibrary()) as _FakeLibrary;
      library.librarySongsList.assignAll([
        _song('aroundTheW', 'Around the World', 'Daft Punk'),
        _song('otherSong0', 'Other song', 'Someone'),
      ]);
      library.deviceSongs
          .assign(_song('device:1', 'One More Time', 'Daft Punk'));
      OfflinePlayback.offline.value = true;
      c.searchFailed.value = true;
      c.isResultContentFetced.value = true;
      await pumpBody(tester);

      // Still says why, with Retry.
      expect(find.text('searchOffline'), findsOneWidget);
      expect(find.text('retry'), findsOneWidget);
      expect(find.text('fromYourLibrary'), findsOneWidget);
      expect(find.text('Around the World'), findsOneWidget);
      expect(find.text('One More Time'), findsOneWidget);
      expect(find.text('Other song'), findsNothing);

      await tester.tap(find.text('One More Time'));
      await tester.pump();
      expect(player.playedList!.map((s) => s.id), ['aroundTheW', 'device:1']);
      expect(player.playedIndex, 1);
      expect(player.playedFrom!.name, 'fromYourLibrary');
    });

    testWidgets('Library › Songs narrowed by its own search: all searched',
        (tester) async {
      Get.put<PlayerController>(_FakePlayer());
      Get.put<SettingsScreenController>(_FakeSettings());
      final library =
          Get.put<LibrarySongsController>(_FakeLibrary()) as _FakeLibrary;
      final aroundTheWorld =
          _song('aroundTheW', 'Around the World', 'Daft Punk');
      final other = _song('otherSong0', 'Other song', 'Someone');
      // Typed "other" there: the list shows that one, all kept aside.
      library.tempListContainer = [aroundTheWorld, other];
      library.librarySongsList.assign(other);
      OfflinePlayback.offline.value = true;
      c.searchFailed.value = true;
      c.isResultContentFetced.value = true;
      await pumpBody(tester);
      expect(find.text('Around the World'), findsOneWidget);
      expect(find.text('Other song'), findsNothing);
    });

    testWidgets('nothing in your library for it: as before', (tester) async {
      Get.put<LibrarySongsController>(_FakeLibrary())
          .librarySongsList
          .assign(_song('otherSong0', 'Other song', 'Someone'));
      OfflinePlayback.offline.value = true;
      c.searchFailed.value = true;
      c.isResultContentFetced.value = true;
      await pumpBody(tester);
      expect(find.text('searchOffline'), findsOneWidget);
      expect(find.text('fromYourLibrary'), findsNothing);
    });

    testWidgets('offline, it says you are', (tester) async {
      OfflinePlayback.offline.value = true;
      c.searchFailed.value = true;
      c.isResultContentFetced.value = true;
      await pumpBody(tester);
      expect(find.text('searchOffline'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });
  });

  test('library matches: every word, accents aside, each song once, a few', () {
    final songs = [
      _song('a', 'Déjà Vu', 'Beyoncé'),
      _song('b', 'Deja vu', 'Olivia Rodrigo'),
      _song('a', 'Déjà Vu', 'Beyoncé'),
      _song('c', 'Halo', 'Beyonce'),
    ];
    expect(librarySearchMatches('deja vu', songs).map((s) => s.id), ['a', 'b']);
    expect(librarySearchMatches('beyonce', songs).map((s) => s.id), ['a', 'c']);
    expect(librarySearchMatches('vu', songs, limit: 1).map((s) => s.id), ['a']);
    expect(librarySearchMatches('  ', songs), isEmpty);
  });
}
