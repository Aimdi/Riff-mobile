import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/services/network_kind.dart';
import 'package:harmonymusic/services/wifi_only_downloads.dart';
import 'package:hive/hive.dart';

/// Downloads without the network: records what it would have written.
class _Downloader extends Downloader {
  final written = <String>[];

  @override
  Future<void> writeFileStream(MediaItem song) async => written.add(song.id);
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

/// Lets the waiting download look at the connection again.
Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var onMobileData = true;

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    onMobileData = true;
    WifiOnlyDownloads.metered = () async => onMobileData;
    WifiOnlyDownloads.poll = const Duration(milliseconds: 1);
  });
  tearDown(() async {
    await WifiOnlyDownloads.set(false);
    WifiOnlyDownloads.metered = NetworkKind.isMetered;
    WifiOnlyDownloads.poll = const Duration(seconds: 15);
    await Hive.close();
  });

  test('off by default: downloads go on mobile data as before', () async {
    expect(WifiOnlyDownloads.enabled.value, isFalse);
    var told = 0;
    expect(
        await WifiOnlyDownloads.waitForWifi(
            wanted: () => true, onWait: () => told++),
        isTrue);
    expect(told, 0);
  });

  test('on: kept, and nothing waits on Wi-Fi', () async {
    await WifiOnlyDownloads.set(true);
    expect(Hive.box('AppPrefs').get(WifiOnlyDownloads.key), isTrue);
    onMobileData = false;
    var told = 0;
    expect(
        await WifiOnlyDownloads.waitForWifi(
            wanted: () => true, onWait: () => told++),
        isTrue);
    expect(told, 0);
  });

  test('on mobile data it waits, says so once, and goes on on Wi-Fi', () async {
    await WifiOnlyDownloads.set(true);
    var told = 0;
    var done = false;
    final wait =
        WifiOnlyDownloads.waitForWifi(wanted: () => true, onWait: () => told++)
          ..then((_) => done = true);
    await _tick();
    await _tick();
    expect(done, isFalse);
    expect(told, 1);
    onMobileData = false;
    expect(await wait, isTrue);
    expect(told, 1);
  });

  test('called off while it waits: it stops there', () async {
    await WifiOnlyDownloads.set(true);
    var wanted = true;
    final wait = WifiOnlyDownloads.waitForWifi(wanted: () => wanted);
    await _tick();
    wanted = false;
    expect(await wait, isFalse);
  });

  test('turning the setting off ends the wait straight away', () async {
    await WifiOnlyDownloads.set(true);
    WifiOnlyDownloads.poll = const Duration(hours: 1);
    final wait = WifiOnlyDownloads.waitForWifi(wanted: () => true);
    await _tick();
    await WifiOnlyDownloads.set(false);
    expect(await wait.timeout(const Duration(seconds: 5)), isTrue);
  });

  group('the downloader', () {
    test('holds the songs until Wi-Fi, then downloads them all', () async {
      await WifiOnlyDownloads.set(true);
      final d = _Downloader();
      d.songQueue.addAll([_song('a'), _song('b')]);
      final job = d.downloadSongList(d.songQueue.toList());
      await _tick();
      expect(d.written, isEmpty);
      expect(d.waitingForWifi.value, isTrue);

      onMobileData = false;
      await job;
      expect(d.written, ['a', 'b']);
      expect(d.waitingForWifi.value, isFalse);
      expect(d.songQueue, isEmpty);
    });

    test('a playlist download cancelled while it waits downloads nothing',
        () async {
      await WifiOnlyDownloads.set(true);
      final d = _Downloader();
      final songs = [_song('a'), _song('b')];
      d.playlistQueue['PL1'] = songs;
      d.currentPlaylistId.value = 'PL1';
      final job = d.downloadSongList(songs, isPlaylist: true);
      await _tick();
      d.playlistQueue.remove('PL1');
      await job.timeout(const Duration(seconds: 5));
      expect(d.written, isEmpty);
      expect(d.waitingForWifi.value, isFalse);
      expect(d.currentPlaylistId.value, '');
    });

    test('on Wi-Fi, or with the setting off, it downloads at once', () async {
      final d = _Downloader();
      await d.downloadSongList([_song('a')]);
      expect(d.written, ['a']);
      await WifiOnlyDownloads.set(true);
      onMobileData = false;
      await d.downloadSongList([_song('b')]);
      expect(d.written, ['a', 'b']);
    });
  });
}
