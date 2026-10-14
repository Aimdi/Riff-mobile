import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_starred.dart';
import 'package:harmonymusic/services/sync/sync_records.dart';
import 'package:harmonymusic/services/sync/webdav_sync_service.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'fake_dav.dart';

MediaItem _episode(int n) => MediaItem(
      id: 'podcast_$n',
      title: 'Episode $n',
      artist: 'One',
      extras: {
        'isPodcast': true,
        'feedUrl': 'https://one.example/feed',
        'url': 'https://one.example/$n.mp3',
        'description': 'Notes for $n',
      },
    );

List<String> _starred() => [for (final s in StarredEpisodes.all) s.id];

/// Starred episodes through the real sync service, on real Hive boxes,
/// against an in-memory WebDAV server; devices are simulated by wiping the
/// boxes in between.
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
    'SyncLedger',
    StarredEpisodes.box,
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
    tmp = await Directory.systemTemp.createTemp('starred_sync_test');
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

  test('starred on one device, on the others; unstarred everywhere', () async {
    await newDevice('aaaa');
    final t0 = DateTime.now().subtract(const Duration(hours: 1));
    await StarredEpisodes.star(_episode(1), now: t0);
    await StarredEpisodes.star(_episode(2),
        now: t0.add(const Duration(minutes: 1)));
    var out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    final file = jsonDecode(dav.files['/dav/Riff/podcasts/starred.json']!)
        as Map<String, dynamic>;
    final record = (file['records'] as Map)['podcast_1'] as Map;
    expect(record['data']['enclosureUrl'], 'https://one.example/1.mp3');
    expect(record['data']['feedUrl'], 'https://one.example/feed');
    expect(record['data']['starredAt'], t0.millisecondsSinceEpoch);

    // A second device gets both, notes and all, newest starred first.
    await newDevice('bbbb');
    out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    expect(_starred(), ['podcast_2', 'podcast_1']);
    final item = StarredEpisodes.entry('podcast_1')!.item!;
    expect(item.title, 'Episode 1');
    expect(item.extras?['url'], 'https://one.example/1.mp3');
    expect(item.extras?['description'], 'Notes for 1');
    // Taking them in is no change of its own.
    out = await WebDavSyncService.syncNow();
    expect(out.sent, 0);

    // It unstars one; a third device has only the other.
    await StarredEpisodes.unstar('podcast_2');
    out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    await newDevice('cccc');
    out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    expect(_starred(), ['podcast_1']);
  });

  test("another app's star (by the audio URL) becomes ours", () async {
    await newDevice('aaaa');
    final at = DateTime.now().millisecondsSinceEpoch - 60000;
    dav.folders.addAll({'/dav/Riff/', '/dav/Riff/podcasts/'});
    dav.files['/dav/Riff/podcasts/starred.json'] = jsonEncode({
      'format': 'riff-sync',
      'version': 1,
      'collection': 'podcast.starred',
      'records': {
        'url:https://two.example/9.mp3': {
          'updatedAt': at,
          'device': 'other',
          'data': {
            'title': 'Nine',
            'show': 'Two',
            'feedUrl': 'https://two.example/feed',
            'enclosureUrl': 'https://two.example/9.mp3',
            'guid': 'ep-9',
          },
        },
      },
    });
    dav.etags['/dav/Riff/podcasts/starred.json'] = '"1"';
    final out = await WebDavSyncService.syncNow();
    expect(out.ok, isTrue, reason: '${out.error}');
    final id = riffRssEpisodeId(
        guid: 'ep-9', enclosureUrl: 'https://two.example/9.mp3');
    expect(_starred(), [id]);
    final item = StarredEpisodes.entry(id)!.item!;
    expect(item.title, 'Nine');
    expect(item.artist, 'Two');
    expect(item.extras?['url'], 'https://two.example/9.mp3');
    expect(item.extras?['feedUrl'], 'https://two.example/feed');
  });
}
