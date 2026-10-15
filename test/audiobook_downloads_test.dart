import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobook_downloads.dart';
import 'package:harmonymusic/services/download_notice.dart';
import 'package:harmonymusic/services/network_kind.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/services/resumable_download.dart';
import 'package:harmonymusic/services/wifi_only_downloads.dart';
import 'package:hive/hive.dart';

/// Audiobooks downloaded to listen offline, as Audible and the
/// Audiobookshelf app keep them: each chapter's file on the phone, played
/// from there with no server and no connection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late HttpServer server;
  // Paths asked for, in order; refused (404); held after a first part
  // until released.
  final asked = <String>[];
  final refused = <String>{};
  final held = <String, Completer<void>>{};

  List<int> audioOf(String path) =>
      List<int>.generate(4096, (i) => (i * 7 + path.length) % 251);

  MediaItem chapter(String book, int i, {bool free = false}) => MediaItem(
        id: free ? 'lv_${book}_$i' : 'abs_${book}_$i',
        title: 'Chapter ${i + 1}',
        album: 'Book $book',
        artist: 'An Author',
        duration: const Duration(minutes: 30),
        artUri: Uri.parse('http://127.0.0.1:${server.port}/$book/cover'),
        extras: {
          'url': 'http://127.0.0.1:${server.port}/$book/$i.mp3?token=t',
          if (free) 'audiobookId': book else 'absItemId': book,
          if (free) 'audiobookTrackIndex': i else 'absTrackIndex': i,
          // The server's listening session of when it was downloaded.
          'absSessionId': 'session-then',
          'album': {'name': 'Book $book', 'id': book},
        },
      );

  List<MediaItem> book(String id, int chapters, {bool free = false}) =>
      [for (var i = 0; i < chapters; i++) chapter(id, i, free: free)];

  Directory bookDir(String id) =>
      Directory('${tmp.path}/audiobook_downloads/$id');

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  setUp(() async {
    // Real sockets to the local server below (the test binding fakes HTTP).
    HttpOverrides.global = null;
    tmp = await Directory.systemTemp.createTemp('book_downloads');
    AudiobookDownloads.baseDir = () async => tmp;
    await Hive.openBox(AudiobookDownloads.boxName, bytes: Uint8List(0));
    ResumableDownload.retryDelay = const Duration(milliseconds: 1);
    asked.clear();
    refused.clear();
    held.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      asked.add(path);
      final response = request.response;
      try {
        if (refused.contains(path)) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        final audio = audioOf(path);
        response.contentLength = audio.length;
        final hold = held[path];
        if (hold != null) {
          // Sent now, not when the buffer fills.
          response.bufferOutput = false;
          response.add(audio.sublist(0, 1024));
          await response.flush();
          await hold.future;
          response.add(audio.sublist(1024));
        } else {
          response.add(audio);
        }
        await response.close();
      } catch (_) {
        // Called off by the phone meanwhile.
      }
    });
  });

  tearDown(() async {
    for (final hold in held.values) {
      if (!hold.isCompleted) hold.complete();
    }
    ResumableDownload.retryDelay = const Duration(seconds: 2);
    WifiOnlyDownloads.enabled.value = false;
    WifiOnlyDownloads.metered = NetworkKind.isMetered;
    WifiOnlyDownloads.poll = const Duration(seconds: 15);
    DownloadNotice.resetForTest();
    await OfflinePlayback.resetForTest();
    await server.close(force: true);
    await Hive.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('downloaded: each chapter on the phone, and played from there',
      () async {
    final chapters = book('b1', 3);
    expect(AudiobookDownloads.isDownloaded('b1'), isFalse);
    expect(
        await AudiobookDownloads.download('b1', chapters), BookDownload.done);
    expect(AudiobookDownloads.isDownloaded('b1'), isTrue);
    expect(AudiobookDownloads.isDownloading('b1'), isFalse);
    // The chapters, then the cover.
    expect(asked, ['/b1/0.mp3', '/b1/1.mp3', '/b1/2.mp3', '/b1/cover']);

    for (final c in chapters) {
      final path = AudiobookDownloads.localPath(c.id);
      expect(path, isNotNull);
      expect(path, startsWith(bookDir('b1').path));
      expect(File(path!).readAsBytesSync(),
          audioOf(Uri.parse(c.extras!['url'] as String).path));
    }

    // The player plays the file, the chapter's address kept.
    final extras = Map<String, dynamic>.from(chapters.first.extras!);
    final url = extras['url'] as String;
    expect(AudiobookDownloads.playUrl(chapters.first.id, url, extras),
        'file://${AudiobookDownloads.localPath(chapters.first.id)}');
    expect(extras['remoteUrl'], url);

    // What plays it with no server: the chapters as they were.
    final kept = AudiobookDownloads.chapters('b1')!;
    expect(kept.map((c) => c.id), chapters.map((c) => c.id));
    expect(kept.first.title, 'Chapter 1');
    expect(kept.first.album, 'Book b1');
    expect(kept.first.artist, 'An Author');
    expect(kept.first.duration, const Duration(minutes: 30));
    // The cover kept with the book, so it shows with no connection.
    final cover = '${bookDir('b1').path}/cover';
    expect(kept.first.artUri, Uri.file(cover));
    expect(kept.last.artUri, Uri.file(cover));
    expect(File(cover).readAsBytesSync(), audioOf('/b1/cover'));
    expect(AudiobookDownloads.coverOf('b1'), Uri.file(cover).toString());
    expect(kept[1].extras!['absItemId'], 'b1');
    expect(kept[1].extras!['absTrackIndex'], 1);
    expect(kept[1].extras!['url'], chapters[1].extras!['url']);
    // Not a listening session long closed.
    expect(kept[1].extras!.containsKey('absSessionId'), isFalse);
  });

  test('a cover that can\'t be had: the book is downloaded all the same',
      () async {
    refused.add('/b9/cover');
    expect(await AudiobookDownloads.download('b9', book('b9', 1)),
        BookDownload.done);
    final kept = AudiobookDownloads.chapters('b9')!;
    expect(kept.single.artUri, book('b9', 1).single.artUri);
    expect(AudiobookDownloads.coverOf('b9'), isNull);
    expect(File('${bookDir('b9').path}/cover').existsSync(), isFalse);
    expect(File('${bookDir('b9').path}/cover.part').existsSync(), isFalse);
  });

  test('the books downloaded, the latest first; LibriVox\'s are free',
      () async {
    await AudiobookDownloads.download('older', book('older', 1));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AudiobookDownloads.download('newer', book('newer', 2, free: true));
    final books = AudiobookDownloads.books();
    expect(books.map((b) => b.id), ['newer', 'older']);
    expect(books.first.title, 'Book newer');
    expect(books.first.author, 'An Author');
    expect(books.first.art, contains('/newer/cover'));
    expect(books.first.free, isTrue);
    expect(books.last.free, isFalse);
  });

  test(
      'a chapter that can\'t be had: not downloaded, and the next try goes '
      'on from it', () async {
    refused.add('/b2/1.mp3');
    expect(await AudiobookDownloads.download('b2', book('b2', 3)),
        BookDownload.failed);
    expect(AudiobookDownloads.isDownloaded('b2'), isFalse);
    expect(AudiobookDownloads.chapters('b2'), isNull);
    expect(AudiobookDownloads.localPath('abs_b2_0'), isNull);

    refused.clear();
    expect(await AudiobookDownloads.download('b2', book('b2', 3)),
        BookDownload.done);
    // The first chapter wasn't fetched again.
    expect(asked,
        ['/b2/0.mp3', '/b2/1.mp3', '/b2/1.mp3', '/b2/2.mp3', '/b2/cover']);
    expect(AudiobookDownloads.isDownloaded('b2'), isTrue);
  });

  test('Cancel stops it in the middle of a chapter, its files gone', () async {
    held['/b3/1.mp3'] = Completer<void>();
    final result = AudiobookDownloads.download('b3', book('b3', 3));
    expect(AudiobookDownloads.isDownloading('b3'), isTrue);
    await until(() => (AudiobookDownloads.progress['b3'] ?? 0) > 1 / 3);
    // The download notification: the book, a chapter of three on its way.
    final notice = DownloadNotice.shown();
    expect(notice['text'], 'Book b3');
    expect(notice['done'], 1);
    expect(notice['total'], 3);

    AudiobookDownloads.cancel('b3');
    expect(await result, BookDownload.cancelled);
    expect(AudiobookDownloads.isDownloading('b3'), isFalse);
    expect(AudiobookDownloads.isDownloaded('b3'), isFalse);
    expect(bookDir('b3').existsSync(), isFalse);
    expect(asked, isNot(contains('/b3/2.mp3')));
    expect(DownloadNotice.shown()['total'], 0);
  });

  test(
      'books download one after another; one waiting its turn can be '
      'cancelled', () async {
    held['/p/0.mp3'] = Completer<void>();
    final first = AudiobookDownloads.download('p', book('p', 2));
    final second = AudiobookDownloads.download('q', book('q', 2));
    final third = AudiobookDownloads.download('r', book('r', 1));
    expect(AudiobookDownloads.progress.keys, ['p', 'q', 'r']);
    await until(() => asked.isNotEmpty);

    AudiobookDownloads.cancel('q');
    held['/p/0.mp3']!.complete();
    expect(await first, BookDownload.done);
    expect(await second, BookDownload.cancelled);
    expect(await third, BookDownload.done);
    expect(asked, ['/p/0.mp3', '/p/1.mp3', '/p/cover', '/r/0.mp3', '/r/cover']);
    expect(AudiobookDownloads.isDownloaded('q'), isFalse);
  });

  test(
      'the connection lost in a chapter: it waits for it, and Cancel ends '
      'the wait', () async {
    held['/b7/0.mp3'] = Completer<void>();
    final result = AudiobookDownloads.download('b7', book('b7', 2));
    await until(() => (AudiobookDownloads.progress['b7'] ?? 0) > 0);
    OfflinePlayback.noConnection.value = true;
    await server.close(force: true);
    await until(() => DownloadNotice.shown()['text'] == 'waitingForConnection');
    expect(AudiobookDownloads.isDownloading('b7'), isTrue);

    AudiobookDownloads.cancel('b7');
    expect(await result, BookDownload.cancelled);
    expect(bookDir('b7').existsSync(), isFalse);
  });

  test('Remove: gone from the phone; it plays from where it streams again',
      () async {
    final chapters = book('b4', 2);
    await AudiobookDownloads.download('b4', chapters);
    final extras = Map<String, dynamic>.from(chapters.first.extras!);
    final remote = extras['url'] as String;
    // As the queue keeps it once it has played from the phone.
    final played =
        AudiobookDownloads.playUrl(chapters.first.id, remote, extras);

    await AudiobookDownloads.remove('b4');
    expect(AudiobookDownloads.isDownloaded('b4'), isFalse);
    expect(AudiobookDownloads.books(), isEmpty);
    expect(bookDir('b4').existsSync(), isFalse);
    expect(AudiobookDownloads.localPath(chapters.first.id), isNull);
    expect(
        AudiobookDownloads.playUrl(chapters.first.id, played, extras), remote);
    // Never downloaded: as it was.
    expect(AudiobookDownloads.playUrl('abs_none_0', remote, {}), remote);
  });

  test('Download on Wi-Fi only: on mobile data it waits for Wi-Fi', () async {
    WifiOnlyDownloads.enabled.value = true;
    var metered = true;
    WifiOnlyDownloads.metered = () async => metered;
    WifiOnlyDownloads.poll = const Duration(milliseconds: 5);
    final result = AudiobookDownloads.download('b5', book('b5', 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(asked, isEmpty);
    expect(AudiobookDownloads.isDownloading('b5'), isTrue);
    expect(DownloadNotice.shown()['text'], 'waitingForWifi');

    metered = false;
    expect(await result, BookDownload.done);
    expect(asked, ['/b5/0.mp3', '/b5/cover']);
  });

  test('a book whose download stopped a week ago: its chapters deleted',
      () async {
    File stopped(String id) => File('${bookDir(id).path}/abs_${id}_0.mp3')
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [1, 2, 3]);
    final weekAgo = DateTime.now().subtract(const Duration(days: 8));
    stopped('old').setLastModifiedSync(weekAgo);
    stopped('recent');
    await AudiobookDownloads.download('kept', book('kept', 1));
    // A book downloaded long ago stays, of course.
    File(AudiobookDownloads.localPath('abs_kept_0')!)
        .setLastModifiedSync(weekAgo);

    await AudiobookDownloads.download('b8', book('b8', 1));
    expect(bookDir('old').existsSync(), isFalse);
    expect(bookDir('recent').existsSync(), isTrue);
    expect(AudiobookDownloads.localPath('abs_kept_0'), isNotNull);
  });

  test('the downloads are known again after a restart', () async {
    final chapters = book('b6', 2, free: true);
    await AudiobookDownloads.download('b6', chapters);
    final path = AudiobookDownloads.localPath(chapters.last.id);
    final stored = Map<dynamic, dynamic>.from(
        Hive.box(AudiobookDownloads.boxName).toMap());

    // Riff closed and started again.
    await Hive.close();
    expect(AudiobookDownloads.isDownloaded('b6'), isFalse);
    expect(AudiobookDownloads.localPath(chapters.last.id), isNull);
    final box =
        await Hive.openBox(AudiobookDownloads.boxName, bytes: Uint8List(0));
    await box.putAll(stored);
    expect(AudiobookDownloads.isDownloaded('b6'), isTrue);
    expect(AudiobookDownloads.localPath(chapters.last.id), path);
    expect(
        AudiobookDownloads.chapters('b6')!.last.extras!['audiobookId'], 'b6');
  });
}
