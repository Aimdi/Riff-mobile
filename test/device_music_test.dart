import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/device_music.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';

/// A song as DeviceMusic.kt lists it.
Map<String, Object?> _row(String id,
        {String title = 'Song',
        String? artist = 'Artist',
        String? art = '/data/covers/album_7.jpg'}) =>
    {
      'id': id,
      'uri': 'content://media/external/audio/media/$id',
      'title': title,
      'artist': artist,
      'album': 'Album',
      'albumId': '7',
      'durationMs': 215000,
      'addedSec': 1760000000,
      if (art != null) 'art': art,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

  test('a music file as Riff plays it, cover and all', () {
    final song = deviceSong(_row('42'))!;
    expect(song.id, 'device_42');
    expect(song.title, 'Song');
    expect(song.artist, 'Artist');
    expect(song.album, 'Album');
    expect(song.duration, const Duration(milliseconds: 215000));
    expect(song.extras?['url'], 'content://media/external/audio/media/42');
    expect(song.artUri, Uri.file('/data/covers/album_7.jpg'));
    // When it came onto the phone (Date added).
    expect(song.extras?['date'], 1760000000 * 1000);
    // Kept through playlists and the saved queue (MediaItemBuilder).
    expect(song.extras?['artists'], [
      {'name': 'Artist'},
    ]);
    expect(DeviceMusic.isDeviceSong(song), isTrue);
  });

  test("MediaStore's <unknown> artist, and no cover", () {
    final song = deviceSong(_row('1', artist: '<unknown>', art: null))!;
    expect(song.artist, isNull);
    expect(song.extras?.containsKey('artists'), isFalse);
    expect(song.artUri, isNull);
  });

  test('nothing to play without its address', () {
    expect(deviceSong({..._row('1'), 'uri': ''}), isNull);
    expect(deviceSong({..._row('1'), 'uri': 'file:///sdcard/a.mp3'}), isNull);
    expect(deviceSong({..._row('1')}..remove('id')), isNull);
  });

  test('plays offline: it needs no connection', () {
    expect(OfflinePlayback.needsConnection(deviceSong(_row('1'))!), isFalse);
  });

  group('over the channels', () {
    final asked = <String>[];
    Object? listed;
    var permissionAnswer = 1; // PermissionStatus.granted
    final requested = <Object?>[];

    setUp(() {
      asked.clear();
      requested.clear();
      permissionAnswer = 1;
      listed = [_row('2', title: 'Beta'), _row('1', title: 'Alpha')];
      DeviceMusic.sdkInt = () => 34;
      DeviceMusic.coverFolder = () async => '/data/covers';
      messenger.setMockMethodCallHandler(DeviceMusic.channel, (call) async {
        asked.add('${call.method} ${(call.arguments as Map)['artDir']}');
        return listed;
      });
      messenger.setMockMethodCallHandler(permissions, (call) async {
        if (call.method == 'requestPermissions') {
          requested.addAll(call.arguments as List);
        }
        return {for (final p in call.arguments as List) p: permissionAnswer};
      });
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(DeviceMusic.channel, null);
      messenger.setMockMethodCallHandler(permissions, null);
    });

    test('the songs, with the covers folder', () async {
      final songs = await DeviceMusic.songs();
      expect(songs!.map((s) => s.title), ['Beta', 'Alpha']);
      expect(asked, ['songs /data/covers']);
    });

    test("none listed when Android won't say (no permission)", () async {
      listed = null;
      expect(await DeviceMusic.songs(), isNull);
    });

    test("Android 13's audio permission, or storage before it", () async {
      expect(await DeviceMusic.askAccess(), isTrue);
      expect(requested, [33]); // Permission.audio
      DeviceMusic.sdkInt = () => 30;
      requested.clear();
      expect(await DeviceMusic.askAccess(), isTrue);
      expect(requested, [15]); // Permission.storage
      permissionAnswer = 0; // denied
      expect(await DeviceMusic.askAccess(), isFalse);
    });

    test('Songs › On this phone: asks, then lists them', () async {
      final library = LibrarySongsController()..showCloudSongs.value = true;
      await library.toggleDeviceSongs();
      expect(library.showDeviceSongs.value, isTrue);
      // One or the other.
      expect(library.showCloudSongs.value, isFalse);
      expect(library.deviceAccess.value, isTrue);
      expect(library.deviceSongs.map((s) => s.id), ['device_2', 'device_1']);
      expect(library.deviceLoading.value, isFalse);

      await library.toggleDeviceSongs();
      expect(library.showDeviceSongs.value, isFalse);
    });

    test("Songs' sort sorts them too, and keeps them so", () async {
      Map<String, Object?> song(String title, int ms, int added) =>
          {..._row(title, title: title), 'durationMs': ms, 'addedSec': added};
      listed = [
        song('Alpha', 300000, 2),
        song('Beta', 100000, 1),
        song('Gamma', 200000, 3),
      ];
      final library = LibrarySongsController();
      await library.toggleDeviceSongs();
      List<String> titles() => [for (final s in library.deviceSongs) s.title];
      expect(titles(), ['Alpha', 'Beta', 'Gamma']);

      library.onSort(SortType.Duration, true);
      expect(titles(), ['Beta', 'Gamma', 'Alpha']);
      // Newest on the phone first.
      library.onSort(SortType.Date, false);
      expect(titles(), ['Gamma', 'Alpha', 'Beta']);

      // Listed again (Allow), still in that order.
      await library.loadDeviceSongs();
      expect(titles(), ['Gamma', 'Alpha', 'Beta']);
    });

    test('refused: it says so, and lists nothing', () async {
      permissionAnswer = 0;
      final library = LibrarySongsController();
      await library.toggleDeviceSongs();
      expect(library.deviceAccess.value, isFalse);
      expect(library.deviceSongs, isEmpty);
      expect(asked, isEmpty);
    });

    test('only on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(DeviceMusic.available, isFalse);
      expect(await DeviceMusic.songs(), isEmpty);
      expect(await DeviceMusic.askAccess(), isFalse);
      expect(asked, isEmpty);
    });
  });

  test('a song from the phone keeps playing from its file after a restart', () {
    // As the saved queue and playlists keep it.
    const stored = MediaItem(
      id: 'device_9',
      title: 'Kept',
      extras: {'url': 'content://media/external/audio/media/9'},
    );
    expect(DeviceMusic.isDeviceSong(stored), isTrue);
    expect(OfflinePlayback.needsConnection(stored), isFalse);
  });
}
