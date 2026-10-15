import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/services/pending_downloads.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/collection_header.dart';
import 'package:hive/hive.dart';

/// Downloads without the network: each song's next tries go as [script]
/// says, then it's written.
class _Downloader extends Downloader {
  final tries = <String>[];
  final written = <String>[];

  /// Per song, what its next tries do: 'lost' (the connection goes with
  /// it), 'broken' (broken off, the connection still there) or 'error'
  /// (it can't be downloaded).
  final script = <String, List<String>>{};

  @override
  Future<void> writeFileStream(MediaItem song) async {
    tries.add(song.id);
    final next = script[song.id];
    if (next != null && next.isNotEmpty) {
      switch (next.removeAt(0)) {
        case 'lost':
          OfflinePlayback.noConnection.value = true;
          throw const DownloadInterrupted('connection lost');
        case 'broken':
          throw const DownloadInterrupted('broken off');
        case 'error':
          throw Exception('not downloadable');
      }
    }
    written.add(song.id);
    await Hive.box('SongDownloads').put(song.id, {'videoId': song.id});
  }
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

/// Lets the waiting download look again.
Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 5));

/// Downloads wait for a connection, as Spotify's and YouTube Music's wait
/// for the network, instead of failing each song in turn.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    await Hive.openBox(PendingDownloads.boxName, bytes: Uint8List(0));
    Downloader.retryDelay = const Duration(milliseconds: 1);
  });
  tearDown(() async {
    Downloader.retryDelay = const Duration(seconds: 2);
    await OfflinePlayback.resetForTest();
    Get.reset();
    await Hive.close();
  });

  test('no connection: the songs wait, and all download once it is back',
      () async {
    OfflinePlayback.noConnection.value = true;
    final d = _Downloader();
    d.songQueue.addAll([_song('a'), _song('b')]);
    final job = d.downloadSongList(d.songQueue.toList());
    await _tick();
    expect(d.tries, isEmpty);
    expect(d.waitingForConnection.value, isTrue);

    OfflinePlayback.noConnection.value = false;
    await job;
    expect(d.written, ['a', 'b']);
    expect(d.waitingForConnection.value, isFalse);
    expect(d.songQueue, isEmpty);
  });

  test('the connection lost on a song: that one again once back, then on',
      () async {
    final d = _Downloader()
      ..script['a'] = ['lost']
      ..songQueue.addAll([_song('a'), _song('b')]);
    final job = d.downloadSongList(d.songQueue.toList());
    await _tick();
    // Not passed over: it waits.
    expect(d.tries, ['a']);
    expect(d.written, isEmpty);
    expect(d.waitingForConnection.value, isTrue);
    expect(d.songQueue.map((s) => s.id), ['a', 'b']);

    OfflinePlayback.noConnection.value = false;
    await job;
    expect(d.tries, ['a', 'a', 'b']);
    expect(d.written, ['a', 'b']);
  });

  test('lost again and again: it waits each time and still gets there',
      () async {
    final d = _Downloader()
      ..script['a'] = ['lost', 'lost', 'lost', 'lost']
      ..songQueue.add(_song('a'));
    final job = d.downloadSongList(d.songQueue.toList());
    for (var i = 0; i < 4; i++) {
      await _tick();
      expect(d.waitingForConnection.value, isTrue);
      OfflinePlayback.noConnection.value = false;
    }
    await job;
    expect(d.written, ['a']);
  });

  test('broken off with the connection there: tried twice more, then left',
      () async {
    final d = _Downloader()
      ..script['a'] = ['broken', 'broken', 'broken']
      ..script['b'] = ['broken'];
    await d.downloadSongList([_song('a'), _song('b'), _song('c')]);
    expect(d.tries, ['a', 'a', 'a', 'b', 'b', 'c']);
    expect(d.written, ['b', 'c']);
  });

  test('a song that can\'t be downloaded is passed over at once, as before',
      () async {
    final d = _Downloader()..script['a'] = ['error'];
    await d.downloadSongList([_song('a'), _song('b')]);
    expect(d.tries, ['a', 'b']);
    expect(d.written, ['b']);
  });

  test('a playlist download cancelled while it waits downloads nothing',
      () async {
    OfflinePlayback.noConnection.value = true;
    final d = _Downloader();
    final songs = [_song('a'), _song('b')];
    d.playlistQueue['PL1'] = songs;
    d.currentPlaylistId.value = 'PL1';
    final job = d.downloadSongList(songs, isPlaylist: true);
    await _tick();
    d.playlistQueue.remove('PL1');
    await job.timeout(const Duration(seconds: 5));
    expect(d.tries, isEmpty);
    expect(d.waitingForConnection.value, isFalse);
    expect(d.currentPlaylistId.value, '');
  });

  test('a song taken off the queue while it waits is left out', () async {
    OfflinePlayback.noConnection.value = true;
    final d = _Downloader()..songQueue.addAll([_song('a'), _song('b')]);
    final job = d.downloadSongList(d.songQueue.toList());
    await _tick();
    d.songQueue.removeWhere((s) => s.id == 'a');
    await _tick();
    OfflinePlayback.noConnection.value = false;
    await job.timeout(const Duration(seconds: 5));
    expect(d.written, ['b']);
  });

  testWidgets('a playlist waiting for a connection says so on its button',
      (tester) async {
    final d = Get.put<Downloader>(_Downloader());
    d.playlistQueue['PL1'] = [_song('a')];
    d.currentPlaylistId.value = 'PL1';
    d.waitingForConnection.value = true;
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: CollectionDownloadButton(
          id: 'PL1',
          songs: () => [_song('a')],
          isDownloaded: false,
          tooltip: 'downloadPlaylist',
        ),
      ),
    ));
    // Queued (the hourglass), not downloading.
    expect(find.byTooltip('waitingForConnection'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_bottom_rounded), findsOneWidget);
    expect(find.text('0/1'), findsNothing);

    d.waitingForConnection.value = false;
    await tester.pump();
    expect(find.byTooltip('waitingForConnection'), findsNothing);
    expect(find.text('0/1'), findsOneWidget);
    // The queue kept for the next start, meanwhile.
    await tester.pump(Downloader.keepDelay);
  });
}
