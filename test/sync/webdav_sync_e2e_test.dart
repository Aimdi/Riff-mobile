import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/sync/webdav_sync_service.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'fake_dav.dart';

/// The real sync service, on real Hive boxes, against an in-memory WebDAV
/// server. Devices are simulated by wiping the boxes in between.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late FakeDav dav;

  const boxes = [
    'AppPrefs',
    'PodcastSubs',
    'PodcastProgress',
    'PodcastPlayed',
    'PodcastBookmarks',
    'PodcastManualSegments',
    'LibraryPlaylists',
    'LIBFAV',
    'LIB1',
    'SyncLedger',
  ];

  Future<void> newDevice(String id) async {
    for (final b in boxes) {
      await Hive.box(b).clear();
    }
    await Hive.box('AppPrefs').put('syncDeviceId', id);
    await WebDavSyncService.saveAccount(
        url: 'https://cloud.example.com/dav', user: 'me', password: 'secret');
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('webdav_sync_test');
    Hive.init(p.join(tmp.path, 'hive'));
    for (final b in boxes) {
      await Hive.openBox(b);
    }
    dav = FakeDav();
    WebDavSyncService.clientFactory = (url, user, pass) => client(dav);
  });

  tearDown(() async {
    WebDavSyncService.clientFactory = null;
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('everything reaches a new device, changes come back, a race is retried',
      () async {
    // ── Device A has data and syncs first.
    await newDevice('aaaa');
    final t0 = DateTime.now().millisecondsSinceEpoch - 60000;
    await Hive.box('PodcastSubs').putAll({
      'https://one.example/feed': {
        'title': 'One',
        'author': 'Host One',
        'artwork': 'https://one.example/a.jpg',
        'feedUrl': 'https://one.example/feed',
        'subscribedAt': t0,
      },
      'https://two.example/feed': {
        'title': 'Two',
        'feedUrl': 'https://two.example/feed',
      },
    });
    await Hive.box('PodcastProgress').put('podcast_7', {
      'id': 'podcast_7',
      'title': 'Episode 7',
      'artist': 'One',
      'url': 'https://one.example/7.mp3',
      'feedUrl': 'https://one.example/feed',
      'positionMs': 600000,
      'durationMs': 3600000,
      'updatedAt': t0,
    });
    await Hive.box('PodcastPlayed').put('podcast_6', t0);
    await Hive.box('PodcastBookmarks').put('podcast_7_$t0', {
      'id': 'podcast_7_$t0',
      'episodeId': 'podcast_7',
      'positionMs': 120000,
      'createdAt': t0,
      'quote': 'a good line',
      'note': 'remember this',
      'episodeTitle': 'Episode 7',
      'showTitle': 'One',
      'episode': {'id': 'podcast_7', 'title': 'Episode 7', 'extras': {}},
    });
    await Hive.box('PodcastManualSegments').put('podcast_7', [
      const PodcastSegment(
              id: 'm_1',
              start: 10,
              end: 70,
              category: SegmentCategory.sponsor,
              source: SegmentSource.manual)
          .toJson()
    ]);
    await Hive.box('LibraryPlaylists').put('LIB1', {
      'title': 'Road trip',
      'playlistId': 'LIB1',
      'description': 'Library Playlist',
      'thumbnails': [
        {'url': 'https://t/road.jpg'}
      ],
      'isPipedPlaylist': false,
      'isCloudPlaylist': false,
    });
    await Hive.box('LIB1').addAll([
      {'videoId': 's1', 'title': 'Song 1', 'duration': 200},
      {'videoId': 's2', 'title': 'Song 2', 'duration': 180},
    ]);
    await Hive.box('LIBFAV').put('s9', {'videoId': 's9', 'title': 'Fav'});

    var out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    expect(out.sent, 6);
    expect(
        dav.files.keys,
        containsAll([
          '/dav/Riff/manifest.json',
          '/dav/Riff/podcasts/subscriptions.opml',
          '/dav/Riff/podcasts/episodes.json',
          '/dav/Riff/podcasts/bookmarks.json',
          '/dav/Riff/podcasts/segments.json',
          '/dav/Riff/library/playlists.json',
          '/dav/Riff/library/favorites.json',
        ]));
    expect(dav.files['/dav/Riff/podcasts/subscriptions.opml'],
        contains('xmlUrl="https://two.example/feed"'));

    // A second sync with nothing new writes nothing.
    out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue);
    expect(out.sent, 0);
    expect(out.received, 0);

    // ── Device B starts with one favourite of its own and gets it all.
    await newDevice('bbbb');
    await Hive.box('LIBFAV').put('s8', {'videoId': 's8', 'title': 'Mine'});
    out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    expect(
        Hive.box('PodcastSubs').keys,
        unorderedEquals(
            ['https://one.example/feed', 'https://two.example/feed']));
    expect(Hive.box('PodcastSubs').get('https://one.example/feed')['author'],
        'Host One');
    final row = Hive.box('PodcastProgress').get('podcast_7') as Map;
    expect(row['positionMs'], 600000);
    expect(row['url'], 'https://one.example/7.mp3');
    expect(Hive.box('PodcastPlayed').containsKey('podcast_6'), isTrue);
    final bm = Hive.box('PodcastBookmarks').get('podcast_7_$t0') as Map;
    expect(bm['note'], 'remember this');
    expect(PodcastSegmentStore.manual('podcast_7').single.start, 10);
    expect(Hive.box('LibraryPlaylists').get('LIB1')['title'], 'Road trip');
    expect([for (final s in Hive.box('LIB1').values) (s as Map)['videoId']],
        ['s1', 's2']);
    expect(Hive.box('LIBFAV').keys, unorderedEquals(['s8', 's9']));
    // Taking all that in is not a change of B's own.
    out = await WebDavSyncService.syncNow();
    expect(out.sent, 0);

    // B unsubscribes, listens on, and loses a race on the episodes file.
    await Hive.box('PodcastSubs').delete('https://two.example/feed');
    final row2 = Map<String, dynamic>.from(row)
      ..['positionMs'] = 900000
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await Hive.box('PodcastProgress').put('podcast_7', row2);
    await Hive.box('LIB1').add({'videoId': 's3', 'title': 'Song 3'});
    dav.raceOn = '/dav/Riff/podcasts/episodes.json';
    out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    expect(dav.raceOn, isNull);

    // ── Device C sees B's changes.
    await newDevice('cccc');
    out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue);
    expect(Hive.box('PodcastSubs').keys, ['https://one.example/feed']);
    expect((Hive.box('PodcastProgress').get('podcast_7') as Map)['positionMs'],
        900000);
    expect(Hive.box('LIB1').length, 3);
    expect(Hive.box('LIBFAV').keys, unorderedEquals(['s8', 's9']));
    expect(dav.files['/dav/Riff/podcasts/subscriptions.opml'],
        contains('riff:tombstone xmlUrl="https://two.example/feed"'));
  });

  test('a newer format on the server is left alone', () async {
    await newDevice('aaaa');
    dav.folders
        .addAll(['/dav/Riff/', '/dav/Riff/podcasts/', '/dav/Riff/library/']);
    dav.files['/dav/Riff/manifest.json'] =
        '{"format":"riff-sync","version":99}';
    dav.etags['/dav/Riff/manifest.json'] = '"m"';
    await Hive.box('PodcastSubs')
        .put('https://x/feed', {'title': 'X', 'feedUrl': 'https://x/feed'});
    final out = await WebDavSyncService.syncNow();
    expect(out.ok, isFalse);
    expect(dav.files.keys, ['/dav/Riff/manifest.json']);
  });

  test('a wrong password says so', () async {
    await newDevice('aaaa');
    dav.password = 'changed';
    final out = await WebDavSyncService.syncNow();
    expect(out.ok, isFalse);
    expect(WebDavSyncService.lastError.value, 'auth');
  });

  test('each sync and connection check closes its client', () async {
    await newDevice('aaaa');
    expect((await WebDavSyncService.syncNow()).ok, isTrue);
    expect(dav.closed, 1);
    dav.password = 'changed';
    expect((await WebDavSyncService.syncNow()).ok, isFalse);
    expect(dav.closed, 2);
    expect(
        await WebDavSyncService.testConnection(
            'https://cloud.example.com/dav', 'me', 'secret'),
        isNotNull);
    expect(dav.closed, 3);
  });
}
