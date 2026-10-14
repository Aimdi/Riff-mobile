import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/chapter_now_playing.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Announces what it's told to, as Riff's handler does.
class _Handler extends BaseAudioHandler {
  var told = 0;

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name != 'showChapter') return;
    told++;
    final shown = chapterShown(mediaItem.value, extras);
    if (shown != null) mediaItem.add(shown);
  }
}

final _showArt = Uri.parse('https://example.com/show.jpg');
const _guestArt = 'https://example.com/guest.jpg';

final _episode = MediaItem(
  id: 'podcast_1',
  title: 'Episode 12',
  artist: 'The Show',
  artUri: _showArt,
  duration: const Duration(hours: 1),
  extras: const {'isPodcast': true, 'feedUrl': 'https://example.com/feed'},
);

final _chapters = [
  PodcastChapter(startSec: 30, title: 'Intro'),
  PodcastChapter(startSec: 60, title: 'The interview', imageUrl: _guestArt),
  PodcastChapter(startSec: 600, title: '  '),
];

void main() {
  group('what shows', () {
    test('the chapter playing in place of the show', () {
      expect(chapterNowPlaying(_episode, _chapters, 10), same(_episode));

      final intro = chapterNowPlaying(_episode, _chapters, 45);
      expect(intro.title, 'Episode 12');
      expect(intro.artist, 'Intro');
      expect(intro.artUri, _showArt);
      expect(intro.id, _episode.id);
      expect(intro.extras, _episode.extras);
    });

    test("with the chapter's own art, unless it isn't wanted", () {
      final interview = chapterNowPlaying(_episode, _chapters, 61);
      expect(interview.artist, 'The interview');
      expect(interview.artUri.toString(), _guestArt);

      expect(chapterNowPlaying(_episode, _chapters, 61, art: false).artUri,
          _showArt);
    });

    test('a chapter with no title shows the show; art not on the web, none',
        () {
      expect(chapterNowPlaying(_episode, _chapters, 700).artist, 'The Show');
      final local = [
        PodcastChapter(startSec: 0, title: 'One', imageUrl: 'chapter.jpg'),
      ];
      expect(chapterNowPlaying(_episode, local, 5).artUri, _showArt);
    });
  });

  group('what the handler announces', () {
    test('only for the item told about, and only a change', () {
      final told = {
        'id': 'podcast_1',
        'artist': 'The interview',
        'artUri': _guestArt,
      };
      final shown = chapterShown(_episode, told)!;
      expect(shown.artist, 'The interview');
      expect(shown.artUri.toString(), _guestArt);
      expect(shown.title, 'Episode 12');
      expect(shown.duration, const Duration(hours: 1));

      expect(chapterShown(shown, told), isNull, reason: 'shown already');
      expect(chapterShown(_episode, {...told, 'id': 'podcast_2'}), isNull);
      expect(chapterShown(null, told), isNull);
      expect(
          chapterShown(shown,
                  {'id': 'podcast_1', 'artist': 'The Show', 'artUri': null})!
              .artUri,
          isNull);
    });
  });

  group('the player', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late PlayerController player;
    late _Handler handler;

    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      Get.put<MusicServices>(_FakeMusic());
      player = Get.put(PlayerController());
      handler = _Handler();
    });
    tearDown(() async {
      Get.delete<PlayerController>();
      // End the controller's wait for the audio handler.
      Get.put<AudioHandler>(_Handler());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Get.reset();
      OfflinePlayback.offline.value = false;
      await Hive.close();
    });

    /// Runs [body] with [handler] there, all at once: the player's own
    /// start, which would find it at its next look, needs AudioService.
    void withHandler(void Function() body) {
      Get.put<AudioHandler>(handler);
      try {
        body();
      } finally {
        Get.delete<AudioHandler>();
      }
    }

    void play(MediaItem item) {
      handler.mediaItem.add(item);
      player.currentSong.value = item;
    }

    test('the chapter playing shows outside the app as it plays', () {
      withHandler(() {
        play(_episode);
        player.chapters.assignAll(_chapters);

        player.onPlaybackPosition(const Duration(seconds: 10));
        expect(handler.mediaItem.value, same(_episode), reason: 'no chapter');

        player.onPlaybackPosition(const Duration(seconds: 45));
        expect(handler.mediaItem.value!.artist, 'Intro');
        expect(handler.mediaItem.value!.artUri, _showArt);

        player.onPlaybackPosition(const Duration(seconds: 61));
        expect(handler.mediaItem.value!.artist, 'The interview');
        expect(handler.mediaItem.value!.artUri.toString(), _guestArt);

        // Told once a chapter.
        final told = handler.told;
        player.onPlaybackPosition(const Duration(seconds: 62));
        expect(handler.told, told);

        // Announced afresh (a queue edit): the chapter shows again.
        handler.mediaItem.add(_episode);
        player.onPlaybackPosition(const Duration(seconds: 63));
        expect(handler.mediaItem.value!.artist, 'The interview');

        // Back before the first chapter: the episode as it was.
        player.onPlaybackPosition(const Duration(seconds: 5));
        expect(handler.mediaItem.value!.artist, 'The Show');
        expect(handler.mediaItem.value!.artUri, _showArt);
      });
      // The player's own song is the episode as it is.
      expect(player.currentSong.value!.artist, 'The Show');
    });

    test("offline, the chapter's art isn't fetched", () {
      OfflinePlayback.offline.value = true;
      withHandler(() {
        play(_episode);
        player.chapters.assignAll(_chapters);
        player.onPlaybackPosition(const Duration(seconds: 61));
      });
      expect(handler.mediaItem.value!.artist, 'The interview');
      expect(handler.mediaItem.value!.artUri, _showArt);
    });

    test('not over a playback error, which it would clear', () {
      player.playbackError.value = 'networkError';
      withHandler(() {
        play(_episode);
        player.chapters.assignAll(_chapters);
        player.onPlaybackPosition(const Duration(seconds: 61));
      });
      expect(handler.told, 0);
      expect(player.playbackError.value, 'networkError');
    });

    test('music is left as it is', () {
      const song = MediaItem(id: 'dQw4w9WgXcQ', title: 'Song', artist: 'Band');
      withHandler(() {
        play(song);
        player.chapters.assignAll(_chapters);
        player.onPlaybackPosition(const Duration(seconds: 61));
      });
      expect(handler.told, 0);
      expect(handler.mediaItem.value!.artist, 'Band');
    });
  });
}
