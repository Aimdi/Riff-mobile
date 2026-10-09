import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_download_service.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late HttpServer server;
  late int hits;
  late Completer<void> release;
  final audio = List<int>.generate(64 * 1024, (i) => i % 251);

  setUp(() async {
    // Real sockets to the local server below (the test binding fakes HTTP).
    HttpOverrides.global = null;
    tmp = await Directory.systemTemp.createTemp('podcast_dl_dedupe');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tmp.path);
    Hive.init('${tmp.path}/hive');
    await Hive.openBox('PodcastDownloads');

    hits = 0;
    release = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      hits++;
      await release.future;
      req.response.contentLength = audio.length;
      req.response.add(audio);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('asking twice while downloading joins the running download', () async {
    final episode = MediaItem(
      id: 'podcast_dup',
      title: 'Episode',
      extras: {'url': 'http://127.0.0.1:${server.port}/ep.mp3'},
    );
    final first = PodcastDownloadService.download(episode);
    final second = PodcastDownloadService.download(episode);
    release.complete();

    expect(await Future.wait([first, second]), [true, true]);
    expect(hits, 1);
    final path = PodcastDownloadService.localPath('podcast_dup');
    expect(path, isNotNull);
    expect(File(path!).readAsBytesSync(), audio);

    // Once finished, a new request is answered from the saved file.
    expect(await PodcastDownloadService.download(episode), isTrue);
    expect(hits, 1);
  });
}
