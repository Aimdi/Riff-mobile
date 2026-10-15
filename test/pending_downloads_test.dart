import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/services/pending_downloads.dart';
import 'package:hive/hive.dart';

/// Downloads without the network or a permission prompt: records what it
/// would have written, and keeps it as downloaded.
class _Downloader extends Downloader {
  _Downloader({this.canResume = true});

  /// Storage access granted already (else resuming would have to ask).
  final bool canResume;
  final written = <String>[];

  @override
  Future<bool> canResumeWithoutAsking() async => canResume;

  @override
  Future<bool> checkPermissionNDir() async => true;

  @override
  Future<void> writeFileStream(MediaItem song) async {
    written.add(song.id);
    await Hive.box('SongDownloads').put(song.id, MediaItemBuilder.toJson(song));
  }
}

MediaItem _song(String id) => MediaItem(
    id: id, title: 'Song $id', artist: 'Artist', extras: const {'length': ''});

bool _downloaded(String id) => Hive.box('SongDownloads').containsKey(id);

/// Lets the downloader keep its queues (it waits [Downloader.keepDelay]).
Future<void> _settle() => Future<void>.delayed(
    Downloader.keepDelay + const Duration(milliseconds: 300));

/// The download queue kept across restarts, as Spotify's and YouTube
/// Music's: what Android closing Riff, a crash or a restart cut off goes on
/// at the next start.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    for (final name in [
      'AppPrefs',
      'SongDownloads',
      PendingDownloads.boxName
    ]) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  group('the store', () {
    test('keeps the songs and each playlist\'s, and gives back what\'s left',
        () async {
      await PendingDownloads.mirror([
        _song('a'),
        _song('b'),
        _song('c'),
      ], {
        'PL1': [_song('c'), _song('d')],
      });
      expect(PendingDownloads.isEmpty, isFalse);

      final left = PendingDownloads.load(isDownloaded: _downloaded);
      // Songs on their own; a playlist's songs come with it.
      expect(left.songs.map((s) => s.id), ['a', 'b']);
      expect(left.playlists.keys, ['PL1']);
      expect(left.playlists['PL1']!.map((s) => s.id), ['c', 'd']);
      expect(left.songs.first.title, 'Song a');
    });

    test('follows the queue: a song done is gone, the queue empty is empty',
        () async {
      await PendingDownloads.mirror([_song('a'), _song('b')], {});
      await PendingDownloads.mirror([_song('b')], {});
      expect(
          PendingDownloads.load(isDownloaded: _downloaded)
              .songs
              .map((s) => s.id),
          ['b']);
      await PendingDownloads.mirror([], {});
      expect(PendingDownloads.isEmpty, isTrue);
    });

    test('downloaded meanwhile: left out, and a playlist all there is done',
        () async {
      await PendingDownloads.mirror([
        _song('a'),
        _song('b')
      ], {
        'PL1': [_song('c')],
      });
      await Hive.box('SongDownloads').put('a', {'videoId': 'a'});
      await Hive.box('SongDownloads').put('c', {'videoId': 'c'});
      final left = PendingDownloads.load(isDownloaded: _downloaded);
      expect(left.songs.map((s) => s.id), ['b']);
      expect(left.playlists, isEmpty);
    });

    test('a damaged entry loses that song only', () async {
      await PendingDownloads.mirror([_song('a'), _song('b')], {});
      await Hive.box(PendingDownloads.boxName).put('a', 'not a song');
      expect(
          PendingDownloads.load(isDownloaded: _downloaded)
              .songs
              .map((s) => s.id),
          ['b']);
    });
  });

  group('the downloader', () {
    test('what a restart cut off is downloaded at the next start', () async {
      // Queued, then Riff stops before the job gets to them.
      final before = Get.put<Downloader>(_Downloader()) as _Downloader;
      before.playlistQueue['PL1'] = [_song('c'), _song('d')];
      before.songQueue.addAll([_song('a'), _song('c'), _song('d')]);
      await _settle();
      expect(PendingDownloads.isEmpty, isFalse);
      Get.reset();

      final after = Get.put<Downloader>(_Downloader()) as _Downloader;
      await after.resumePending();
      // The playlist shows as downloading again.
      expect(after.playlistQueue.keys, ['PL1']);
      while (after.isJobRunning.isTrue) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(after.written..sort(), ['a', 'c', 'd']);
      // All done: nothing left for the next start.
      await _settle();
      expect(PendingDownloads.isEmpty, isTrue);
    });

    test('a playlist download called off is not resumed', () async {
      final d = Get.put<Downloader>(_Downloader()) as _Downloader;
      d.playlistQueue['PL1'] = [_song('c')];
      d.songQueue.add(_song('c'));
      await _settle();
      d.playlistQueue.remove('PL1');
      d.songQueue.clear();
      await _settle();
      expect(PendingDownloads.isEmpty, isTrue);
    });

    test('needing to ask for storage at start: they go with your next one',
        () async {
      await PendingDownloads.mirror([_song('a')], {});
      final d =
          Get.put<Downloader>(_Downloader(canResume: false)) as _Downloader;
      await d.resumePending();
      expect(d.songQueue, isEmpty);
      // Not dropped meanwhile.
      expect(PendingDownloads.isEmpty, isFalse);

      await d.download(_song('b'));
      expect(d.written..sort(), ['a', 'b']);
    });

    test('a playlist left from last time, downloaded again, is not cancelled',
        () async {
      await PendingDownloads.mirror([
        _song('c')
      ], {
        'PL1': [_song('c')],
      });
      final d =
          Get.put<Downloader>(_Downloader(canResume: false)) as _Downloader;
      // Its download button, tapped: the leftovers come back first, and the
      // tap still downloads it (rather than calling it off).
      await d.downloadPlaylist('PL1', [_song('c'), _song('e')]);
      expect(d.written..sort(), ['c', 'e']);
    });

    test('nothing left: nothing queued', () async {
      final d = Get.put<Downloader>(_Downloader()) as _Downloader;
      await d.resumePending();
      expect(d.songQueue, isEmpty);
      expect(d.isJobRunning.value, isFalse);
    });
  });
}
