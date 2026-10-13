import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/pending_file_deletes.dart';
import 'package:harmonymusic/services/podcast_download_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;
  late File episode;

  Map pending() =>
      (Hive.box('AppPrefs').get(pendingFileDeletesKey) as Map?) ?? {};

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_pod_dl_undo_');
    Hive.init('${tmp.path}/hive');
    await Hive.openBox('AppPrefs');
    await Hive.openBox('PodcastDownloads');
    episode = File('${tmp.path}/ep1.mp3')..writeAsStringSync('audio');
    await Hive.box('PodcastDownloads')
        .put('ep1', {'id': 'ep1', 'path': episode.path, 'title': 'Ep 1'});
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('undo brings the download back, file and all', () async {
    final removal = await PodcastDownloadService.takeOut('ep1');
    expect(removal, isNotNull);
    expect(PodcastDownloadService.isDownloaded('ep1'), isFalse);
    // The file waits for Undo.
    expect(episode.existsSync(), isTrue);
    expect(pending().keys, [podcastDownloadPendingKey('ep1')]);

    await PodcastDownloadService.restore(removal!);
    expect(PodcastDownloadService.isDownloaded('ep1'), isTrue);
    expect(PodcastDownloadService.localPath('ep1'), episode.path);
    expect(pending(), isEmpty);
  });

  test('without undo the file is deleted', () async {
    final removal = await PodcastDownloadService.takeOut('ep1');
    await PodcastDownloadService.commitRemoval(removal!);
    expect(episode.existsSync(), isFalse);
    expect(PodcastDownloadService.isDownloaded('ep1'), isFalse);
    expect(pending(), isEmpty);
  });

  test('downloaded again meanwhile: the file stays', () async {
    final removal = await PodcastDownloadService.takeOut('ep1');
    await Hive.box('PodcastDownloads')
        .put('ep1', {'id': 'ep1', 'path': episode.path});
    await PodcastDownloadService.commitRemoval(removal!);
    expect(episode.existsSync(), isTrue);
  });

  test('old entries stored as a bare path work too', () async {
    await Hive.box('PodcastDownloads').put('ep1', episode.path);
    final removal = await PodcastDownloadService.takeOut('ep1');
    expect(removal!.path, episode.path);
    await PodcastDownloadService.restore(removal);
    expect(Hive.box('PodcastDownloads').get('ep1'), episode.path);
  });

  test('nothing downloaded: nothing to take out', () async {
    expect(await PodcastDownloadService.takeOut('nope'), isNull);
  });

  test('pending keys tell podcast files from library songs', () {
    expect(
        podcastDownloadIdFromPendingKey(podcastDownloadPendingKey('x')), 'x');
    expect(podcastDownloadIdFromPendingKey('dQw4w9WgXcQ'), isNull);
  });
}
