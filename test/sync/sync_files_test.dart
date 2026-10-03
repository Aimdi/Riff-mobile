import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/sync/sync_merge.dart';
import 'package:harmonymusic/services/sync/sync_opml.dart';
import 'package:harmonymusic/services/sync/sync_records.dart';
import 'package:harmonymusic/services/sync/webdav_client.dart';
import 'package:harmonymusic/services/sync/webdav_sync_service.dart';

import 'fake_dav.dart';

void main() {
  group('subscriptions OPML', () {
    test('round trip with times, devices and tombstones', () {
      final records = {
        'https://a.example/feed.xml':
            const SyncRecord(updatedAt: 10, device: 'aa', data: {
          'feedUrl': 'https://a.example/feed.xml',
          'title': 'Alpha & Co',
          'author': 'Host',
          'artwork': 'https://a.example/a.jpg',
        }),
        'https://gone.example/rss':
            const SyncRecord.tombstone(updatedAt: 20, device: 'bb'),
      };
      final xml = encodeSubscriptionsOpml(records, nowMs: 30, device: 'aa');
      expect(xml, contains('xmlns:riff="urn:riff:sync:1"'));
      final back = decodeSubscriptionsOpml(xml);
      expect(back.keys, unorderedEquals(records.keys));
      final a = back['https://a.example/feed.xml']!;
      expect(a.updatedAt, 10);
      expect(a.device, 'aa');
      expect(a.data, records['https://a.example/feed.xml']!.data);
      expect(back['https://gone.example/rss']!.deleted, isTrue);
      expect(back['https://gone.example/rss']!.updatedAt, 20);
    });

    test('other apps read it as plain OPML (tombstones aren\'t outlines)', () {
      final xml = encodeSubscriptionsOpml({
        'https://gone.example/rss':
            const SyncRecord.tombstone(updatedAt: 20, device: 'bb'),
      }, nowMs: 30, device: 'aa');
      expect(xml, isNot(contains('<outline')));
    });

    test('an OPML file from another app counts as time 0, folders included',
        () {
      final back = decodeSubscriptionsOpml('''<?xml version="1.0"?>
<opml version="1.0"><head><title>x</title></head><body>
<outline text="Folder"><outline text="Show" XMLURL="https://s.example/f"
 htmlUrl="https://s.example"/></outline></body></opml>''');
      final r = back['https://s.example/f']!;
      expect(r.updatedAt, 0);
      expect(r.data!['title'], 'Show');
      // Extra attributes survive the next write.
      expect(r.data!['attrs'], {'htmlUrl': 'https://s.example'});
      final again = decodeSubscriptionsOpml(
          encodeSubscriptionsOpml(back, nowMs: 1, device: 'a'));
      expect(again['https://s.example/f']!.data!['attrs'],
          {'htmlUrl': 'https://s.example'});
    });

    test('not OPML is refused', () {
      expect(() => decodeSubscriptionsOpml('{"a":1}'), throwsFormatException);
      expect(() => decodeSubscriptionsOpml('<rss/>'), throwsFormatException);
    });
  });

  group('episodes', () {
    test('progress row to record and back', () {
      final row = {
        'id': 'podcast_42',
        'title': 'Ep',
        'artist': 'Show',
        'artUri': 'https://x/a.jpg',
        'url': 'https://x/ep.mp3',
        'feedUrl': 'https://x/feed',
        'description': 'notes',
        'positionMs': 61000,
        'durationMs': 3600000,
        'updatedAt': 5,
      };
      final data = episodeDataFromProgress('podcast_42', row);
      expect(data, {
        'positionMs': 61000,
        'durationMs': 3600000,
        'played': false,
        'title': 'Ep',
        'show': 'Show',
        'artUri': 'https://x/a.jpg',
        'feedUrl': 'https://x/feed',
        'enclosureUrl': 'https://x/ep.mp3',
      });
      final back = progressRowFromEpisode('podcast_42', data, 99, row);
      expect(back['description'], 'notes'); // kept from before
      expect(back['positionMs'], 61000);
      expect(back['updatedAt'], 99);
      expect(episodeDataFromProgress('podcast_42', back), data);
    });

    test('a downloaded file path is never sent', () {
      final data = episodeDataFromProgress(
          'podcast_1', {'url': 'file:///data/ep.mp3', 'positionMs': 1});
      expect(data.containsKey('enclosureUrl'), isFalse);
    });

    test('YouTube episodes carry their video id', () {
      expect(
          episodeDataFromProgress('dQw4w9WgXcQ', {})['videoId'], 'dQw4w9WgXcQ');
      expect(episodeDataPlayed('dQw4w9WgXcQ'),
          {'positionMs': 0, 'played': true, 'videoId': 'dQw4w9WgXcQ'});
      expect(episodeDataPlayed('podcast_1').containsKey('videoId'), isFalse);
    });

    test('url: ids become ours, with a tombstone for the alias', () {
      const url = 'https://x/ep.mp3';
      final ours = riffRssEpisodeId(guid: 'guid-1', enclosureUrl: url);
      expect(ours, 'podcast_${'guid-1'.hashCode}');
      expect(riffRssEpisodeId(guid: null, enclosureUrl: url),
          'podcast_${url.hashCode}');
      final out = adoptForeignEpisodeIds({
        'url:$url': const SyncRecord(
            updatedAt: 50,
            device: 'desk',
            data: {'positionMs': 5, 'guid': 'guid-1'}),
      }, 'me')!;
      expect(out[ours]!.updatedAt, 50);
      expect(out[ours]!.device, 'desk');
      expect(out[ours]!.data!['positionMs'], 5);
      expect(out['url:$url']!.deleted, isTrue);
      expect(out['url:$url']!.updatedAt, 50);
    });

    test('a newer record under our id is not overwritten', () {
      const url = 'https://x/ep.mp3';
      final ours = riffRssEpisodeId(enclosureUrl: url);
      final out = adoptForeignEpisodeIds({
        'url:$url': const SyncRecord(
            updatedAt: 50, device: 'desk', data: {'positionMs': 5}),
        ours: const SyncRecord(
            updatedAt: 60, device: 'me', data: {'positionMs': 9}),
      }, 'me')!;
      expect(out[ours]!.data!['positionMs'], 9);
    });

    test('nothing to adopt', () {
      expect(
          adoptForeignEpisodeIds({
            'podcast_1': const SyncRecord.tombstone(updatedAt: 1, device: 'a')
          }, 'me'),
          isNull);
    });
  });

  group('bookmarks and segments', () {
    test('bookmark data adds the feed and audio URL, drops the id', () {
      final d = bookmarkData({
        'id': 'podcast_1_5',
        'episodeId': 'podcast_1',
        'positionMs': 1000,
        'createdAt': 5,
        'quote': '',
        'updatedAt': 9,
        'episode': {
          'id': 'podcast_1',
          'extras': {'feedUrl': 'https://f', 'url': 'https://a.mp3'}
        },
      });
      expect(d.containsKey('id'), isFalse);
      expect(d.containsKey('updatedAt'), isFalse);
      expect(d.containsKey('quote'), isFalse); // empty
      expect(d['feedUrl'], 'https://f');
      expect(d['enclosureUrl'], 'https://a.mp3');
    });

    test('segment record ids', () {
      expect(segmentRecordId('podcast_1', 'm_5'), 'podcast_1#m_5');
      final p = parseSegmentRecordId('url:https://x/a#b.mp3#m_5')!;
      expect(p.episodeId, 'url:https://x/a#b.mp3');
      expect(p.segmentId, 'm_5');
      expect(parseSegmentRecordId('nohash'), isNull);
      expect(parseSegmentRecordId('#x'), isNull);
      expect(segmentCreatedAt('m_1767225600000'), 1767225600000);
      expect(segmentCreatedAt('other'), isNull);
    });
  });

  group('playlists', () {
    test('song maps convert both ways', () {
      final stored = {
        'videoId': 'abc',
        'title': 'Song',
        'artists': [
          {'name': 'A', 'id': 'UC1'}
        ],
        'album': null,
        'duration': 213,
        'thumbnails': [
          {'url': 'https://t/1.jpg'}
        ],
        'url': '/storage/emulated/0/song.m4a',
        'description': '',
      };
      final s = syncSongFromStored(stored);
      expect(s, {
        'videoId': 'abc',
        'title': 'Song',
        'artists': [
          {'name': 'A', 'id': 'UC1'}
        ],
        'durationSec': 213,
        'thumbnailUrl': 'https://t/1.jpg',
      });
      final back = storedSongFromSync(s);
      expect(back['duration'], 213);
      expect(back['thumbnails'], [
        {'url': 'https://t/1.jpg'}
      ]);
      expect(syncSongFromStored(back), s);
    });

    test('which playlists sync', () {
      expect(playlistKind({'playlistId': 'LIB1', 'isCloudPlaylist': false}),
          'local');
      expect(playlistKind({'playlistId': 'PL1'}), 'youtube');
      expect(playlistKind({'playlistId': 'LIBFAV'}), isNull);
      expect(
          playlistKind({'playlistId': 'P', 'isPipedPlaylist': true}), isNull);
      expect(playlistKind({'playlistId': 'M', 'kind': 'daily_mix'}), isNull);
    });

    test('saved YouTube playlists sync without songs', () {
      final d = playlistData(
          {'title': 'YT', 'playlistId': 'PL1'},
          'youtube',
          [
            {'videoId': 'a'}
          ]);
      expect(d['songs'], isEmpty);
      final entry = playlistEntryFromSync('PL1', d);
      expect(entry['isCloudPlaylist'], isTrue);
      expect(entry.containsKey('thumbnails'), isFalse);
    });

    test('a local playlist entry round-trips', () {
      final json = {
        'title': 'Road',
        'playlistId': 'LIB9',
        'description': 'Library Playlist',
        'thumbnails': [
          {'url': 'https://t/c.jpg'}
        ],
        'isCloudPlaylist': false,
      };
      final d = playlistData(json, 'local', const []);
      final entry = playlistEntryFromSync('LIB9', d);
      expect(playlistData(entry, playlistKind(entry)!, const []), d);
    });
  });

  group('WebDAV client', () {
    test('URLs: trailing slash and encoded segments', () {
      expect(webDavUrl('https://h/dav', 'Riff/a b.json').toString(),
          'https://h/dav/Riff/a%20b.json');
      expect(webDavUrl('https://h/dav/', 'Riff/podcasts/').toString(),
          'https://h/dav/Riff/podcasts/');
      expect(validWebDavBase('https://h/x'), isTrue);
      expect(validWebDavBase('ftp://h'), isFalse);
      expect(validWebDavBase('nonsense'), isFalse);
    });

    test('check: fine, wrong password, wrong URL', () async {
      final dav = FakeDav();
      await client(dav).check();
      await expectLater(
          client(dav, password: 'nope').check(),
          throwsA(isA<WebDavException>()
              .having((e) => e.error, 'error', WebDavError.auth)));
      dav.folders.clear();
      await expectLater(
          client(dav).check(),
          throwsA(isA<WebDavException>()
              .having((e) => e.error, 'error', WebDavError.notFound)));
    });

    test('folders, then write only over the version read', () async {
      final dav = FakeDav();
      final c = client(dav);
      await c.ensureFolder('Riff/podcasts/');
      await c.ensureFolder('Riff/podcasts/'); // already there: fine
      expect(dav.folders, containsAll(['/dav/Riff/', '/dav/Riff/podcasts/']));

      expect(await c.read('Riff/podcasts/x.json'), isNull);
      await c.write('Riff/podcasts/x.json', '1',
          create: true, contentType: 'application/json');
      final f = (await c.read('Riff/podcasts/x.json'))!;
      expect(f.body, '1');
      // Creating again fails: someone made it in between.
      await expectLater(
          c.write('Riff/podcasts/x.json', '2',
              create: true, contentType: 'application/json'),
          throwsA(isA<WebDavException>()
              .having((e) => e.error, 'error', WebDavError.conflict)));
      await c.write('Riff/podcasts/x.json', '2',
          ifMatch: f.etag, contentType: 'application/json');
      // The old ETag is stale now.
      await expectLater(
          c.write('Riff/podcasts/x.json', '3',
              ifMatch: f.etag, contentType: 'application/json'),
          throwsA(isA<WebDavException>()
              .having((e) => e.error, 'error', WebDavError.conflict)));
      expect((await c.read('Riff/podcasts/x.json'))!.body, '2');
    });

    test('status codes map to errors', () {
      expect(webDavErrorFor(401), WebDavError.auth);
      expect(webDavErrorFor(403), WebDavError.auth);
      expect(webDavErrorFor(404), WebDavError.notFound);
      expect(webDavErrorFor(412), WebDavError.conflict);
      expect(webDavErrorFor(507), WebDavError.server);
    });
  });

  test('automatic syncs are spaced out', () {
    const t = 1000000;
    expect(autoSyncDue(lastAttemptMs: null, nowMs: t), isTrue);
    expect(autoSyncDue(lastAttemptMs: t - 60000, nowMs: t), isFalse);
    expect(autoSyncDue(lastAttemptMs: t - 6 * 60000, nowMs: t), isTrue);
    expect(
        autoSyncDue(
            lastAttemptMs: t - 60000, nowMs: t, gap: autoSyncLeavingGap),
        isTrue);
    // Clock moved back: don't get stuck.
    expect(autoSyncDue(lastAttemptMs: t + 5000, nowMs: t), isTrue);
  });

  test('a collection file survives a full read-merge-write cycle', () {
    const f = SyncFile(collection: 'podcast.bookmarks', records: {
      'b1': SyncRecord(updatedAt: 1, device: 'a', data: {'q': 'x'})
    });
    final m = mergeRecords(const {},
        SyncFile.decode(f.encode(), collection: 'podcast.bookmarks').records,
        nowMs: 2);
    expect(m.remoteChanged, isFalse);
  });
}
