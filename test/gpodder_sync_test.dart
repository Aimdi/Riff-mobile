import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_history.dart';
import 'package:harmonymusic/services/podcast_inbox_cache.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/services/sync/gpodder_sync.dart';
import 'package:harmonymusic/services/sync/sync_records.dart';
import 'package:harmonymusic/ui/screens/Settings/gpodder_sync_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

/// A gpodder server as Nextcloud's GPodder Sync app and gpodder.net serve
/// one: a log of followed / unfollowed shows and of episode actions, each
/// change at the server's own timestamp (a counter here).
class _FakeGpodder {
  late HttpServer server;
  int clock = 1000;
  final changes = <({int at, String feed, bool added})>[];
  final actions = <({int at, Map<String, dynamic> json})>[];
  final requests = <({String method, String path, Object? body})>[];
  String password = 'secret';

  /// Answers 200 with a web page instead (not a gpodder server).
  bool notGpodder = false;

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_answer);
  }

  /// Another app on the same account follows or unfollows a show.
  void otherApp({List<String> add = const [], List<String> remove = const []}) {
    clock++;
    for (final f in add) {
      changes.add((at: clock, feed: f, added: true));
    }
    for (final f in remove) {
      changes.add((at: clock, feed: f, added: false));
    }
  }

  /// Another app plays an episode.
  void otherPlays(Map<String, dynamic> action) {
    clock++;
    actions.add((at: clock, json: action));
  }

  /// The shows the server has as followed now.
  Set<String> get followed {
    final out = <String>{};
    for (final c in changes) {
      c.added ? out.add(c.feed) : out.remove(c.feed);
    }
    return out;
  }

  Future<void> _answer(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final body = text.isEmpty ? null : jsonDecode(text);
    final path = request.uri.path;
    requests.add((method: request.method, path: path, body: body));
    final res = request.response;
    final expected = 'Basic ${base64Encode(utf8.encode('me:$password'))}';
    if (request.headers.value('authorization') != expected) {
      res.statusCode = HttpStatus.unauthorized;
      await res.close();
      return;
    }
    if (notGpodder) {
      res.headers.contentType = ContentType.html;
      res.write('<html>Log in</html>');
      await res.close();
      return;
    }
    final since = int.tryParse(request.uri.queryParameters['since'] ?? '');
    Object? answer;
    if (path.endsWith('/subscriptions') ||
        (path.startsWith('/api/2/subscriptions/') && request.method == 'GET')) {
      final latest = <String, bool>{};
      for (final c in changes) {
        if (c.at > (since ?? 0)) latest[c.feed] = c.added;
      }
      answer = {
        'add': [
          for (final e in latest.entries)
            if (e.value) e.key
        ],
        'remove': [
          for (final e in latest.entries)
            if (!e.value) e.key
        ],
        'timestamp': clock,
      };
    } else if (path.endsWith('/subscription_change/create') ||
        path.startsWith('/api/2/subscriptions/')) {
      clock++;
      for (final f in (body as Map)['add'] as List) {
        changes.add((at: clock, feed: f as String, added: true));
      }
      for (final f in body['remove'] as List) {
        changes.add((at: clock, feed: f as String, added: false));
      }
      answer = {'timestamp': clock};
    } else if ((path.endsWith('/episode_action') ||
            path.startsWith('/api/2/episodes/')) &&
        request.method == 'GET') {
      answer = {
        'actions': [
          for (final a in actions)
            if (a.at > (since ?? 0)) a.json
        ],
        'timestamp': clock,
      };
    } else if (path.endsWith('/episode_action/create') ||
        path.startsWith('/api/2/episodes/')) {
      clock++;
      for (final a in body as List) {
        actions.add((at: clock, json: Map<String, dynamic>.from(a as Map)));
      }
      answer = {'timestamp': clock};
    } else if (path.startsWith('/api/2/devices/')) {
      answer = {};
    } else {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(answer));
    await res.close();
  }

  List<Map<String, dynamic>> uploadedActions() => [
        for (final r in requests)
          if (r.method == 'POST' && r.body is List)
            for (final a in r.body as List) Map<String, dynamic>.from(a as Map)
      ];
}

const _a = 'https://a.example/feed.xml';
const _b = 'https://b.example/feed.xml';
const _c = 'https://c.example/feed.xml';
const _d = 'https://d.example/feed.xml';
const _e = 'https://e.example/feed.xml';
const _f = 'https://f.example/feed.xml';
const _x = 'https://x.example/feed.xml';

/// An episode as the Inbox keeps it.
MediaItem _episode(String id, String feed, String url,
        {String title = 'Episode', int seconds = 3600}) =>
    MediaItem(
      id: id,
      title: title,
      artist: 'Show',
      duration: Duration(seconds: seconds),
      extras: {'url': url, 'feedUrl': feed, 'isPodcast': true},
    );

/// gpodder sync, as AntennaPod, Kasts and gPodder have it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeGpodder fake;
  final unreadable = <String>{};

  Set<String> followedHere() =>
      {for (final s in PodcastService.subscriptions) '${s['feedUrl']}'};

  Future<void> follow(String feed) => PodcastService.subscribe(
      {'title': 'Show', 'author': '', 'artwork': '', 'feedUrl': feed});

  Future<void> signIn({GpodderKind kind = GpodderKind.nextcloud}) =>
      GpodderSync.saveAccount(
          kind: kind, server: fake.base, user: 'me', password: 'secret');

  setUp(() async {
    HttpOverrides.global = null;
    for (final box in [
      'AppPrefs',
      'PodcastSubs',
      'PodcastProgress',
      'PodcastPlayed',
      PodcastHistory.box,
      PodcastInboxCache.box,
    ]) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
    fake = _FakeGpodder();
    await fake.start();
    unreadable.clear();
    GpodderSync.feedInfo = (feed) async => unreadable.contains(feed)
        ? null
        : {
            'title': 'Show at $feed',
            'author': '',
            'artwork': '',
            'feedUrl': feed
          };
    GpodderSync.feedEpisodes = (feed, title, art) async => const [];
    GpodderSync.clock = () => DateTime.utc(2026, 10, 15, 12);
  });

  tearDown(() async {
    GpodderSync.feedInfo = PodcastService.feedInfo;
    GpodderSync.feedEpisodes = PodcastService.episodes;
    GpodderSync.clock = DateTime.now;
    SecureCredentials.resetForTest();
    await fake.server.close(force: true);
    await Hive.close();
  });

  group('followed shows', () {
    test('the first sync joins both lists and unfollows nothing', () async {
      await follow(_a);
      await follow(_b);
      fake.otherApp(add: [_b, _c, _d]);
      fake.otherApp(remove: [_d]);
      await signIn();

      final out = await GpodderSync.syncNow();
      expect(out.ok, isTrue);
      expect(followedHere(), {_a, _b, _c});
      expect(fake.followed, {_a, _b, _c});
      expect(out.followed, 1);
      expect(out.unfollowed, 0);
      // The show came with its name.
      expect(
          PodcastService.subscriptions
              .firstWhere((s) => s['feedUrl'] == _c)['title'],
          'Show at $_c');
    });

    test('then what each side changed since', () async {
      await follow(_a);
      await follow(_b);
      await signIn();
      await GpodderSync.syncNow();

      // Another app unfollows B and follows E; this phone unfollows A and
      // follows F.
      fake.otherApp(remove: [_b], add: [_e]);
      await PodcastService.unsubscribe(_a);
      await follow(_f);

      final out = await GpodderSync.syncNow();
      expect(followedHere(), {_e, _f});
      expect(fake.followed, {_e, _f});
      expect(out.followed, 1);
      expect(out.unfollowed, 1);
    });

    test('a show changed on both sides keeps this phone\'s change', () async {
      await follow(_a);
      await signIn();
      await GpodderSync.syncNow();

      await PodcastService.unsubscribe(_a);
      fake.otherApp(add: [_a]);
      await GpodderSync.syncNow();
      expect(followedHere(), isEmpty);
      expect(fake.followed, isEmpty);
    });

    test('a show whose feed can\'t be read is followed once it can', () async {
      await signIn();
      fake.otherApp(add: [_x]);
      unreadable.add(_x);
      await GpodderSync.syncNow();
      expect(followedHere(), isEmpty);

      unreadable.clear();
      await GpodderSync.syncNow();
      expect(followedHere(), {_x});
    });
  });

  group('episodes', () {
    const u1 = 'https://a.example/1.mp3';
    const u2 = 'https://a.example/2.mp3';
    const u3 = 'https://a.example/3.mp3';
    const u4 = 'https://a.example/4.mp3';
    final id1 = riffRssEpisodeId(enclosureUrl: u1);
    final id2 = riffRssEpisodeId(enclosureUrl: u2);
    final id3 = riffRssEpisodeId(enclosureUrl: u3);
    final id4 = riffRssEpisodeId(guid: 'g4', enclosureUrl: u4);
    Box progress() => Hive.box('PodcastProgress');
    Box played() => Hive.box('PodcastPlayed');
    final noon = DateTime.utc(2026, 10, 15, 12);

    Map<String, dynamic> play(String url,
            {required int position,
            int total = 3600,
            String? guid,
            required DateTime at}) =>
        {
          'podcast': _a,
          'episode': url,
          if (guid != null) 'guid': guid,
          'action': 'play',
          'timestamp': gpodderTimestamp(at),
          'started': 0,
          'position': position,
          'total': total,
        };

    test(
        'where another app is, and what it finished, come in; the newer '
        'side wins', () async {
      await follow(_a);
      await PodcastInboxCache.save([
        _episode(id1, _a, u1, title: 'Ep 1'),
      ], 'subs');
      await PodcastHistory.add(_episode(id2, _a, u2, title: 'Ep 2'));
      // This phone was further into episode 3, and later.
      await progress().put(id3, {
        'id': id3,
        'title': 'Ep 3',
        'url': u3,
        'feedUrl': _a,
        'positionMs': 900000,
        'durationMs': 3600000,
        'updatedAt': noon.millisecondsSinceEpoch,
      });
      // Episode 4 isn't here: its feed has it.
      GpodderSync.feedEpisodes = (feed, title, art) async => [
            {
              'id': id4,
              'title': 'Ep 4',
              'url': u4,
              'artwork': 'https://a.example/4.jpg',
              'durationSec': 1800,
              'description': 'Notes',
            }
          ];
      final hourAgo = noon.subtract(const Duration(hours: 1));
      fake.otherPlays(play(u1, position: 600, at: hourAgo));
      fake.otherPlays(play(u2, position: 3600, at: hourAgo));
      fake.otherPlays(play(u3, position: 120, at: hourAgo));
      fake.otherPlays(
          play(u4, position: 300, total: 1800, guid: 'g4', at: hourAgo));
      await signIn();

      final out = await GpodderSync.syncNow();
      expect(out.ok, isTrue);
      expect(out.episodes, 3);
      final ep1 = progress().get(id1) as Map;
      expect(ep1['title'], 'Ep 1');
      expect(ep1['positionMs'], 600000);
      expect(ep1['durationMs'], 3600000);
      expect(ep1['updatedAt'], hourAgo.millisecondsSinceEpoch);
      // Finished there: played here.
      expect(played().get(id2), hourAgo.millisecondsSinceEpoch);
      expect(progress().containsKey(id2), isFalse);
      // This phone's was newer.
      expect((progress().get(id3) as Map)['positionMs'], 900000);
      final ep4 = progress().get(id4) as Map;
      expect(ep4['title'], 'Ep 4');
      expect(ep4['artist'], 'Show');
      expect(ep4['positionMs'], 300000);
    });

    test(
        'this phone\'s places and finished episodes go up, not back what '
        'came down', () async {
      await follow(_a);
      await PodcastHistory.add(_episode(id2, _a, u2, seconds: 2400));
      await signIn();
      final before = noon.subtract(const Duration(minutes: 30));
      await progress().put(id3, {
        'id': id3,
        'title': 'Ep 3',
        'url': u3,
        'feedUrl': _a,
        'positionMs': 754000,
        'durationMs': 3600000,
        'updatedAt': before.millisecondsSinceEpoch,
      });
      await played().put(id2, before.millisecondsSinceEpoch);
      fake.otherPlays(play(u1, position: 600, at: before));
      await PodcastInboxCache.save([_episode(id1, _a, u1)], 'subs');

      await GpodderSync.syncNow();
      final sent = fake.uploadedActions();
      expect(sent, hasLength(2));
      final ep3 = sent.firstWhere((a) => a['episode'] == u3);
      expect(ep3['podcast'], _a);
      expect(ep3['action'], 'play');
      expect(ep3['position'], 754);
      expect(ep3['total'], 3600);
      expect(ep3['timestamp'], gpodderTimestamp(before));
      expect(ep3.containsKey('device'), isFalse);
      // Finished: played to its end, as AntennaPod sends it.
      final ep2 = sent.firstWhere((a) => a['episode'] == u2);
      expect(ep2['position'], 2400);
      expect(ep2['total'], 2400);

      // Nothing new: nothing goes.
      fake.requests.clear();
      GpodderSync.clock = () => noon.add(const Duration(hours: 1));
      await GpodderSync.syncNow();
      expect(fake.uploadedActions(), isEmpty);
    });
  });

  test('the wrong password, no gpodder sync there, no connection', () async {
    await signIn();
    fake.password = 'changed';
    expect((await GpodderSync.syncNow()).error, GpodderError.auth);
    expect(GpodderSync.lastError.value, 'auth');

    fake.password = 'secret';
    fake.notGpodder = true;
    expect(
        await GpodderSync.testConnection(
            kind: GpodderKind.nextcloud,
            server: fake.base,
            user: 'me',
            password: 'secret'),
        GpodderError.notFound);

    final port = fake.server.port;
    await fake.server.close(force: true);
    expect(
        await GpodderSync.testConnection(
            kind: GpodderKind.nextcloud,
            server: 'http://127.0.0.1:$port',
            user: 'me',
            password: 'secret'),
        GpodderError.network);
    await fake.start();
  });

  test('gpodder.net: its addresses, and this phone as a device', () async {
    await follow(_a);
    await PodcastService.subscribe(
        {'title': 'Show', 'author': '', 'artwork': '', 'feedUrl': _b});
    await signIn(kind: GpodderKind.gpodderNet);
    final device = GpodderSync.device;
    expect(device, startsWith('riff-'));
    expect(fake.requests.first.path, '/api/2/devices/me/$device.json');

    await Hive.box('PodcastProgress').put('podcast_x', {
      'id': 'podcast_x',
      'title': 'X',
      'url': 'https://a.example/x.mp3',
      'feedUrl': _a,
      'positionMs': 60000,
      'durationMs': 600000,
      'updatedAt': DateTime.utc(2026, 10, 15, 11).millisecondsSinceEpoch,
    });
    await GpodderSync.syncNow();
    final paths = {for (final r in fake.requests) '${r.method} ${r.path}'};
    expect(paths, contains('GET /api/2/subscriptions/me/$device.json'));
    expect(paths, contains('POST /api/2/subscriptions/me/$device.json'));
    expect(paths, contains('POST /api/2/episodes/me.json'));
    expect(fake.followed, {_a, _b});
    expect(fake.uploadedActions().single['device'], device);
  });

  testWidgets('the page: the server kind, its address, and saving',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const GpodderSyncScreen(),
    ));
    // FilledButton.icon builds a subclass of FilledButton.
    final save = find.ancestor(
        of: find.text('syncSave'),
        matching: find.byWidgetPredicate((w) => w is FilledButton));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    final fields = find.byType(TextField);
    String address() => tester.widget<TextField>(fields.at(0)).controller!.text;
    // gpodder.net: its own address comes in.
    await tester.tap(find.text('gpodderNet'));
    await tester.pump();
    expect(address(), GpodderSync.gpodderNetServer);
    // Back to Nextcloud: an address to type.
    await tester.tap(find.text('gpodderNextcloud'));
    await tester.pump();
    expect(address(), isEmpty);

    await tester.enterText(fields.at(0), 'https://cloud.example.com');
    await tester.enterText(fields.at(1), 'me');
    await tester.enterText(fields.at(2), 'app-password');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.runAsync(() async {
      await tester.tap(save);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(GpodderSync.configured, isTrue);
    expect(GpodderSync.server, 'https://cloud.example.com');
    expect(GpodderSync.kind, GpodderKind.nextcloud);
    expect(GpodderSync.autoSync, isTrue);
    expect(GpodderSync.password, 'app-password');
  });

  test('Riff still starting: it waits for the next try', () async {
    await signIn();
    await Hive.box('PodcastSubs').close();
    final before = GpodderSync.lastSyncAt.value;
    final out = await GpodderSync.syncNow();
    expect(out.ok, isTrue);
    expect(fake.requests.where((r) => r.method == 'GET'), isEmpty);
    expect(GpodderSync.lastSyncAt.value, before);
  });

  test('gpodder timestamps are UTC to the second', () {
    expect(gpodderTimestamp(DateTime.utc(2026, 10, 15, 3, 4, 5, 678)),
        '2026-10-15T03:04:05');
    expect(gpodderTime('2026-10-15T03:04:05'),
        DateTime.utc(2026, 10, 15, 3, 4, 5));
    expect(gpodderTime('2026-10-15T03:04:05Z'),
        DateTime.utc(2026, 10, 15, 3, 4, 5));
    expect(gpodderTime('2026-10-15T05:04:05+02:00'),
        DateTime.utc(2026, 10, 15, 3, 4, 5));
    expect(gpodderTime(''), isNull);
  });
}
