import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/services/podcast_download_service.dart';
import 'package:harmonymusic/services/resumable_download.dart';
import 'package:hive/hive.dart';

/// A request as the test server got it: its headers (names in lower case)
/// and the connection to answer on.
typedef _Request = ({Map<String, String> headers, Socket socket});

/// What the server answers a request with.
typedef _Answer = Future<void> Function(_Request request);

/// Partial downloads resumed (Range, If-Range), as AntennaPod resumes them:
/// the rest only when the server says it's the same file, else all of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late ServerSocket server;
  final audio = List<int>.generate(64 * 1024, (i) => i % 251);
  final other = List<int>.generate(48 * 1024, (i) => (i * 7) % 253);
  final requests = <Map<String, String?>>[];
  final answers = <_Answer>[];
  var episodes = 0;

  /// Writes a response by hand, so it can stop short: [body] from [from],
  /// [bytes] of it when given (then the connection is cut), else all.
  Future<void> respond(_Request request, List<int> body,
      {required int from, String? etag, int? bytes}) async {
    final partial = request.headers['range'] != null;
    final out = StringBuffer(
        partial ? 'HTTP/1.1 206 Partial Content\r\n' : 'HTTP/1.1 200 OK\r\n')
      ..write('content-length: ${body.length - from}\r\n')
      ..write('connection: close\r\n');
    if (partial) {
      out.write('content-range: bytes $from-${body.length - 1}/'
          '${body.length}\r\n');
    }
    if (etag != null) out.write('etag: $etag\r\n');
    out.write('\r\n');
    final socket = request.socket
      ..add(latin1.encode(out.toString()))
      ..add(body.sublist(from, bytes == null ? null : from + bytes));
    await socket.flush();
    if (bytes != null) {
      socket.destroy();
    } else {
      await socket.close();
    }
  }

  /// [bytes] of [body] (of the part asked for, Range), and the connection
  /// cut.
  _Answer cut(List<int> body, int bytes, {String? etag}) => (request) =>
      respond(request, body, from: _from(request), etag: etag, bytes: bytes);

  /// All of [body], whatever was asked (a server not resuming, or a changed
  /// file).
  _Answer whole(List<int> body, {String? etag}) =>
      (request) => respond((headers: const {}, socket: request.socket), body,
          from: 0, etag: etag);

  /// The part of [body] asked for (Range), with [etag].
  _Answer rest(List<int> body, {String? etag}) =>
      (request) => respond(request, body, from: _from(request), etag: etag);

  MediaItem episode() => MediaItem(
        id: 'podcast_resume${episodes++}',
        title: 'Episode',
        extras: {'url': 'http://127.0.0.1:${server.port}/ep.mp3'},
      );

  List<int> saved(MediaItem e) =>
      File(PodcastDownloadService.localPath(e.id)!).readAsBytesSync();

  Directory downloads() => Directory('${tmp.path}/podcast_downloads');

  setUp(() async {
    // Real sockets to the local server below (the test binding fakes HTTP).
    HttpOverrides.global = null;
    tmp = await Directory.systemTemp.createTemp('podcast_dl_resume');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tmp.path);
    Hive.init('${tmp.path}/hive');
    await Hive.openBox('PodcastDownloads');
    ResumableDownload.retryDelay = const Duration(milliseconds: 1);

    requests.clear();
    answers.clear();
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) async {
      final headers = await _head(socket);
      requests.add({
        'range': headers['range'],
        'if-range': headers['if-range'],
      });
      final answer =
          answers.isNotEmpty ? answers.removeAt(0) : whole(audio, etag: '"v1"');
      await answer((headers: headers, socket: socket));
    });
  });

  tearDown(() async {
    ResumableDownload.retryDelay = const Duration(seconds: 2);
    await OfflinePlayback.resetForTest();
    await server.close();
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('cut off halfway: the next try asks for the rest only', () async {
    answers.addAll(
        [cut(audio, 32 * 1024, etag: '"v1"'), rest(audio, etag: '"v1"')]);
    final e = episode();
    expect(await PodcastDownloadService.download(e), isTrue);
    expect(requests, hasLength(2));
    expect(requests[0]['range'], isNull);
    expect(requests[1]['range'], matches(RegExp(r'^bytes=[1-9]\d*-$')));
    expect(requests[1]['if-range'], '"v1"');
    expect(saved(e), audio);
    // Nothing left over.
    expect(downloads().listSync().map((f) => f.path.split('/').last),
        ['${e.id}.mp3']);
  });

  test('the server sending the whole file: it starts over, not after the part',
      () async {
    answers.addAll([cut(audio, 32 * 1024, etag: '"v1"'), whole(other)]);
    final e = episode();
    expect(await PodcastDownloadService.download(e), isTrue);
    expect(requests[1]['range'], isNotNull);
    expect(saved(e), other);
  });

  test('a part of another file (another ETag) is not joined on', () async {
    answers.addAll([
      cut(audio, 32 * 1024, etag: '"v1"'),
      // A server not minding If-Range: the rest of a changed file.
      rest(other, etag: '"v2"'),
      whole(other, etag: '"v2"'),
    ]);
    final e = episode();
    expect(await PodcastDownloadService.download(e), isTrue);
    expect(requests, hasLength(3));
    expect(requests[2]['range'], isNull);
    expect(saved(e), other);
  });

  test('nothing to tell the file by (no ETag or date): all of it again',
      () async {
    answers.addAll([cut(audio, 32 * 1024), whole(audio)]);
    final e = episode();
    expect(await PodcastDownloadService.download(e), isTrue);
    expect(requests[1]['range'], isNull);
    expect(saved(e), audio);
  });

  test('the connection gone halfway: it waits for it, then gets the rest',
      () async {
    answers.add((request) async {
      OfflinePlayback.noConnection.value = true;
      await cut(audio, 32 * 1024, etag: '"v1"')(request);
    });
    answers.add(rest(audio, etag: '"v1"'));
    final e = episode();
    var done = false;
    final download = PodcastDownloadService.download(e)
      ..then((_) => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(done, isFalse);
    expect(requests, hasLength(1));

    OfflinePlayback.noConnection.value = false;
    expect(await download, isTrue);
    expect(requests[1]['range'], isNotNull);
    expect(saved(e), audio);
  });

  test('offline from the start: it fails at once, as before', () async {
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close(force: true);
    OfflinePlayback.noConnection.value = true;
    final e = MediaItem(
        id: 'podcast_offline',
        title: 'Episode',
        extras: {'url': 'http://127.0.0.1:$port/ep.mp3'});
    expect(
        await PodcastDownloadService.download(e)
            .timeout(const Duration(seconds: 10)),
        isFalse);
  });

  test('broken off three times: given up, what it got kept for next time',
      () async {
    answers.addAll([
      for (var i = 0; i < 3; i++) cut(audio, 8 * 1024, etag: '"v1"'),
    ]);
    final e = episode();
    expect(await PodcastDownloadService.download(e), isFalse);
    expect(requests, hasLength(3));
    expect(PodcastDownloadService.isDownloaded(e.id), isFalse);

    // Tried again later: the rest only.
    answers.add(rest(audio, etag: '"v1"'));
    expect(await PodcastDownloadService.download(e), isTrue);
    expect(requests[3]['range'], isNotNull);
    expect(saved(e), audio);
  });

  test('partial downloads left a week ago are cleared away', () async {
    final dir = downloads()..createSync(recursive: true);
    final old = DateTime.now().subtract(const Duration(days: 8));
    final stale = File('${dir.path}/old.mp3.part')..writeAsBytesSync([1, 2]);
    final staleMeta = File('${dir.path}/old.mp3.part.json')
      ..writeAsStringSync('{}');
    stale.setLastModifiedSync(old);
    staleMeta.setLastModifiedSync(old);
    final recent = File('${dir.path}/recent.mp3.part')..writeAsBytesSync([3]);

    expect(await PodcastDownloadService.download(episode()), isTrue);
    expect(stale.existsSync(), isFalse);
    expect(staleMeta.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
  });
}

/// Where a Range request asks to start.
int _from(_Request request) => int.parse(RegExp(r'bytes=(\d+)-')
    .firstMatch(request.headers['range'] ?? 'bytes=0-')![1]!);

/// A request's headers, read off [socket] (a GET has nothing after them).
Future<Map<String, String>> _head(Socket socket) {
  final head = Completer<Map<String, String>>();
  final got = <int>[];
  socket.listen((chunk) {
    got.addAll(chunk);
    final text = latin1.decode(got);
    final end = text.indexOf('\r\n\r\n');
    if (end < 0 || head.isCompleted) return;
    head.complete({
      for (final line in text.substring(0, end).split('\r\n').skip(1))
        if (line.contains(':'))
          line.substring(0, line.indexOf(':')).trim().toLowerCase():
              line.substring(line.indexOf(':') + 1).trim(),
    });
  }, onError: (_) {});
  return head.future;
}
