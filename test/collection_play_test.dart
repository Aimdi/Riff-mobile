import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/services/discovery/discovery_tag.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/widgets/collection_play.dart';
import 'package:hive/hive.dart';

import 'fakes/fake_music_services.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('collection cards open their page on the body tap', () {
    expect(shouldPlayCollectionOnTap(), isFalse);
  });

  test('system library playlist ids', () {
    expect(isSystemLibraryPlaylistId('LIBFAV'), isTrue);
    expect(isSystemLibraryPlaylistId('LIBRP'), isTrue);
    expect(isSystemLibraryPlaylistId('SongsCache'), isTrue);
    expect(isSystemLibraryPlaylistId('SongDownloads'), isTrue);
    expect(isSystemLibraryPlaylistId('PLabc'), isFalse);
  });

  test('artistTopSongsFromResponse reads Top songs then Songs', () {
    const song = MediaItem(id: 'a', title: 'A');
    expect(
      artistTopSongsFromResponse({
        'Top songs': {
          'content': [song]
        }
      }).map((e) => e.id),
      ['a'],
    );
    expect(
      artistTopSongsFromResponse({
        'Songs': [song]
      }).map((e) => e.id),
      ['a'],
    );
    expect(artistTopSongsFromResponse(const {}), isEmpty);
  });

  test('collection play maps system ids to a discovery source', () {
    expect(sourceFromPlaylistId('LIBFAV'), DiscoverySource.downloads);
    expect(sourceFromPlaylistId('PLuser'), DiscoverySource.playlist);
  });

  group('offline', () {
    late FakeMusicServices music;
    setUp(() {
      music = FakeMusicServices()..error = Exception('offline');
      Get.put<MusicServices>(music);
      Get.put<PlayerController>(_FakePlayer());
    });
    tearDown(Get.reset);

    // These used to throw, past callers that only check for an empty
    // list / false, so the album or artist page never opened as fallback.
    test('collection tracks come back empty', () async {
      expect(
          await loadCollectionPlayTracks(isAlbum: true, id: 'MPREx'), isEmpty);
      expect(
          await loadCollectionPlayTracks(isAlbum: false, id: 'PLx'), isEmpty);
      expect(music.playlistCalls, 2);
    });

    test('playing a collection reports false', () async {
      expect(await playCollection(isAlbum: true, id: 'MPREx', title: 'X'),
          isFalse);
      expect(music.playlistCalls, 1);
    });

    test('a caller that asks for errors still gets the throw', () async {
      // The mood chips say "network error" rather than "empty mix".
      await expectLater(
          playCollection(
              isAlbum: false, id: 'PLx', title: 'X', throwOnError: true),
          throwsException);
    });

    test('playing an artist reports false', () async {
      final artist = Artist(name: 'A', browseId: 'UCx', thumbnailUrl: '');
      expect(await playArtist(artist), isFalse);
      expect(await playArtist(artist, radio: true), isFalse);
      expect(music.artistCalls, 2);
    });
  });

  // Home's long press and Speed dial pins don't say what's in the Library:
  // asked of YouTube Music, your own playlist failed ("Operation failed").
  group('what the Library has, without being told', () {
    late FakeMusicServices music;
    setUp(() async {
      music = FakeMusicServices()..error = Exception('offline');
      Get.put<MusicServices>(music);
      await Hive.openBox('LibraryPlaylists', bytes: Uint8List(0));
      await Hive.openBox('LibraryAlbums', bytes: Uint8List(0));
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    Map<String, dynamic> song(String id) => {
          'videoId': id,
          'title': 'Song $id',
          'artists': [
            {'name': 'Nova Hart', 'id': null}
          ],
        };

    test('your own playlist plays from the phone', () async {
      await Hive.box('LibraryPlaylists').put('LIB1699', {
        'title': 'Road trip',
        'playlistId': 'LIB1699',
        'isCloudPlaylist': false,
      });
      final songs = await Hive.openBox('LIB1699', bytes: Uint8List(0));
      await songs.addAll([song('a'), song('b')]);
      final tracks =
          await loadCollectionPlayTracks(isAlbum: false, id: 'LIB1699');
      expect(tracks.map((t) => t.id), ['a', 'b']);
      expect(music.playlistCalls, 0);
    });

    test('a saved album plays its saved songs, offline too', () async {
      await Hive.box('LibraryAlbums').put('MPREb_coast', {
        'title': 'Coastlines',
        'browseId': 'MPREb_coast',
      });
      final songs = await Hive.openBox('MPREb_coast', bytes: Uint8List(0));
      await songs.add(song('c'));
      final tracks =
          await loadCollectionPlayTracks(isAlbum: true, id: 'MPREb_coast');
      expect(tracks.map((t) => t.id), ['c']);
      expect(music.playlistCalls, 0);
    });
  });
}
