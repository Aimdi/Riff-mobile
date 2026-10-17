/// gpodder sync, as AntennaPod, Kasts and gPodder have it: the shows you
/// follow and where you are in each episode, kept in step with a Nextcloud
/// server running the GPodder Sync app, or with gpodder.net, and so with
/// those apps on your other devices.
///
/// Followed shows go both ways by what changed since the last sync: the
/// server says what was followed and unfollowed since (by its timestamp);
/// what this phone changed since is told by the shows it followed then,
/// kept, against those it follows now. A show changed on both sides keeps
/// this phone's change. The first sync joins both lists and unfollows
/// nothing.
///
/// Episodes go as gpodder "play" actions: where you are and how long the
/// episode is (in seconds), and when. An episode finished (or marked
/// played) goes as played to its end, as AntennaPod sends it, and one that
/// comes so is marked played here. The newer side wins.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/podcast_history.dart';
import '/services/podcast_inbox_cache.dart';
import '/services/podcast_service.dart';
import '/ui/screens/Podcasts/podcast_queue_controller.dart';
import '/utils/helper.dart';
import '/utils/secure_credentials.dart';
import 'sync_records.dart' show riffRssEpisodeId;
import 'webdav_sync_service.dart'
    show autoSyncDue, autoSyncGap, autoSyncLeavingGap;

/// The kind of gpodder server.
enum GpodderKind { nextcloud, gpodderNet }

/// Why a sync (or a check) didn't go through.
enum GpodderError {
  /// The server turned down the user name and password.
  auth,

  /// No gpodder sync at that address (on Nextcloud: the app isn't there).
  notFound,

  /// The server couldn't be reached.
  network,

  /// The server answered something else.
  server,
}

/// How a sync went.
class GpodderOutcome {
  const GpodderOutcome(
      {this.error,
      this.followed = 0,
      this.unfollowed = 0,
      this.episodes = 0,
      this.sent = 0});

  /// Null when it all went through.
  final GpodderError? error;

  /// Shows followed and unfollowed here from the server.
  final int followed;
  final int unfollowed;

  /// Episodes whose place (or played state) came from the server.
  final int episodes;

  /// Changes sent to the server.
  final int sent;

  bool get ok => error == null;
}

/// A gpodder episode action (Riff reads and sends "play" ones).
class GpodderAction {
  const GpodderAction({
    required this.podcast,
    required this.episode,
    this.guid,
    this.action = 'play',
    required this.at,
    this.started = 0,
    this.position = 0,
    this.total = 0,
  });

  /// The show's feed address, and the episode's (its enclosure).
  final String podcast;
  final String episode;
  final String? guid;
  final String action;
  final DateTime at;

  /// Seconds.
  final int started;
  final int position;
  final int total;

  /// Played to its end (or close), as AntennaPod marks a played episode.
  bool get finished =>
      total > 0 && (position >= total - 20 || position >= total * 0.98);

  static GpodderAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final podcast = json['podcast'];
    final episode = json['episode'];
    final at = gpodderTime('${json['timestamp'] ?? ''}');
    if (podcast is! String || episode is! String || at == null) return null;
    final guid = json['guid'];
    return GpodderAction(
      podcast: podcast,
      episode: episode,
      guid: guid is String && guid.isNotEmpty ? guid : null,
      action: '${json['action'] ?? ''}'.toLowerCase(),
      at: at,
      started: _int(json['started']) ?? 0,
      position: _int(json['position']) ?? 0,
      total: _int(json['total']) ?? 0,
    );
  }

  Map<String, dynamic> toJson({String? device}) => {
        'podcast': podcast,
        'episode': episode,
        if (guid != null) 'guid': guid,
        if (device != null) 'device': device,
        'action': action,
        'timestamp': gpodderTimestamp(at),
        'started': started,
        'position': position,
        'total': total,
      };
}

/// gpodder's timestamp: UTC, to the second, without a zone
/// ("2026-10-15T03:00:00").
String gpodderTimestamp(DateTime at) =>
    at.toUtc().toIso8601String().split('.').first.replaceAll('Z', '');

/// A gpodder timestamp, read as UTC when it doesn't say.
DateTime? gpodderTime(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final zoned = t.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(t);
  return DateTime.tryParse(zoned ? t : '${t}Z')?.toUtc();
}

int? _int(Object? v) => v is int
    ? v
    : v is num
        ? v.toInt()
        : int.tryParse('${v ?? ''}');

List<String> _strings(Object? v) => v is List
    ? [
        for (final s in v)
          if (s is String && s.isNotEmpty) s
      ]
    : [];

/// The gpodder JSON API, as Nextcloud's GPodder Sync app and gpodder.net
/// (API 2) serve it, with HTTP Basic sign-in.
class GpodderApi {
  GpodderApi({
    required this.kind,
    required String server,
    required this.user,
    required String password,
    required this.device,
    Dio? dio,
  })  : _base = server.trim().replaceAll(RegExp(r'/+$'), ''),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _auth = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';

  final GpodderKind kind;
  final String user;
  final String device;
  final String _base;
  final Dio _dio;
  final String _auth;

  Options get _options => Options(
      headers: {'authorization': _auth}, responseType: ResponseType.plain);

  String _seg(String s) => Uri.encodeComponent(s);

  String get _nextcloud => '$_base/index.php/apps/gpoddersync';

  String get _subscriptions => kind == GpodderKind.nextcloud
      ? '$_nextcloud/subscriptions'
      : '$_base/api/2/subscriptions/${_seg(user)}/${_seg(device)}.json';

  String get _subscriptionsUp => kind == GpodderKind.nextcloud
      ? '$_nextcloud/subscription_change/create'
      : _subscriptions;

  String get _actions => kind == GpodderKind.nextcloud
      ? '$_nextcloud/episode_action'
      : '$_base/api/2/episodes/${_seg(user)}.json';

  String get _actionsUp =>
      kind == GpodderKind.nextcloud ? '$_actions/create' : _actions;

  static Map _json(Object? data) {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map) throw const FormatException('Not gpodder JSON');
    return decoded;
  }

  /// Shows followed and unfollowed since [since] (seconds), and the
  /// server's timestamp to ask from next time.
  Future<({List<String> add, List<String> remove, int timestamp})>
      subscriptions(int since) async {
    final res = await _dio.get(_subscriptions,
        queryParameters: {'since': since}, options: _options);
    final data = _json(res.data);
    return (
      add: _strings(data['add']),
      remove: _strings(data['remove']),
      timestamp: _int(data['timestamp']) ?? since,
    );
  }

  /// This phone's followed and unfollowed shows; the server's timestamp.
  Future<int?> uploadSubscriptions(
      Iterable<String> add, Iterable<String> remove) async {
    final res = await _dio.post(_subscriptionsUp,
        data: {'add': add.toList(), 'remove': remove.toList()},
        options: _options);
    return _int(_json(res.data)['timestamp']);
  }

  /// Episode actions since [since] (seconds), and the server's timestamp.
  Future<({List<GpodderAction> actions, int timestamp})> episodeActions(
      int since) async {
    final res = await _dio.get(_actions,
        queryParameters: {'since': since}, options: _options);
    final data = _json(res.data);
    final list = data['actions'];
    return (
      actions: [
        if (list is List)
          for (final a in list)
            if (GpodderAction.fromJson(a) case final action?) action
      ],
      timestamp: _int(data['timestamp']) ?? since,
    );
  }

  /// This phone's episode actions; the server's timestamp.
  Future<int?> uploadActions(List<GpodderAction> actions) async {
    final res = await _dio.post(_actionsUp,
        data: [
          for (final a in actions)
            a.toJson(device: kind == GpodderKind.gpodderNet ? device : null)
        ],
        options: _options);
    return _int(_json(res.data)['timestamp']);
  }

  /// gpodder.net keeps subscriptions per device: this phone as one.
  Future<void> registerDevice() async {
    if (kind != GpodderKind.gpodderNet) return;
    await _dio.post('$_base/api/2/devices/${_seg(user)}/${_seg(device)}.json',
        data: {'caption': 'Riff', 'type': 'mobile'}, options: _options);
  }

  void close() => _dio.close();
}

/// What went wrong, from what a call threw.
GpodderError gpodderErrorOf(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) return GpodderError.auth;
    if (status == 404 || status == 405) return GpodderError.notFound;
    if (status == null) return GpodderError.network;
    return GpodderError.server;
  }
  if (e is FormatException) return GpodderError.notFound;
  return GpodderError.server;
}

/// The account (AppPrefs `gpodderSync`, the password in secure storage)
/// and the sync.
class GpodderSync {
  GpodderSync._();

  static const prefsKey = 'gpodderSync';

  /// gpodder.net's address.
  static const gpodderNetServer = 'https://gpodder.net';

  static final syncing = false.obs;

  /// Last finished sync (ms) and its error ('' when fine), for the page.
  static final lastSyncAt = 0.obs;
  static final lastError = ''.obs;

  static int? _lastAttemptMs;
  static Future<GpodderOutcome>? _running;

  /// Most episode actions sent at once.
  static const _batch = 100;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Tests point the sync at a fake server.
  @visibleForTesting
  static GpodderApi Function()? apiFactory;

  /// The show at a feed address ({title, author, artwork, feedUrl}), or
  /// null when it can't be read.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(String feed) feedInfo =
      PodcastService.feedInfo;

  /// A show's episodes, as its feed lists them.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function(
          String feed, String title, String art) feedEpisodes =
      PodcastService.episodes;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static Map<String, dynamic> get _config {
    final v = _prefs?.get(prefsKey);
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  static Future<void> _putConfig(Map<String, dynamic> changes) async {
    await _prefs?.put(prefsKey, {..._config, ...changes});
  }

  static GpodderKind get kind => _config['kind'] == GpodderKind.gpodderNet.name
      ? GpodderKind.gpodderNet
      : GpodderKind.nextcloud;
  static String get server => '${_config['server'] ?? ''}';
  static String get user => '${_config['user'] ?? ''}';
  static String get password =>
      SecureCredentials.nested(prefsKey, 'password') ?? '';
  static bool get autoSync => _config['auto'] == true;
  static bool get configured => server.isNotEmpty && user.isNotEmpty;

  /// This install's gpodder.net device ("riff-" and 8 hex digits).
  static String get device {
    final existing = _config['device'];
    if (existing is String && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final id =
        'riff-${List.generate(4, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    _putConfig({'device': id});
    return id;
  }

  /// Load the last result for the settings page.
  static void loadStatus() {
    final c = _config;
    lastSyncAt.value = _int(c['lastSyncAt']) ?? 0;
    lastError.value = '${c['lastError'] ?? ''}';
  }

  static GpodderApi _api(
          {GpodderKind? kind,
          String? server,
          String? user,
          String? password}) =>
      apiFactory?.call() ??
      GpodderApi(
        kind: kind ?? GpodderSync.kind,
        server: server ?? GpodderSync.server,
        user: user ?? GpodderSync.user,
        password: password ?? GpodderSync.password,
        device: device,
      );

  /// Checks an account before it's saved; null when it works.
  static Future<GpodderError?> testConnection(
      {required GpodderKind kind,
      required String server,
      required String user,
      required String password}) async {
    final api =
        _api(kind: kind, server: server, user: user, password: password);
    try {
      // Nothing since now: a small answer that needs the sign-in.
      await api.subscriptions(clock().millisecondsSinceEpoch ~/ 1000);
      return null;
    } catch (e) {
      return gpodderErrorOf(e);
    } finally {
      api.close();
    }
  }

  /// Saves the account, auto-sync on. Another server or user starts afresh:
  /// what was synced with the old one says nothing about the new one.
  static Future<void> saveAccount(
      {required GpodderKind kind,
      required String server,
      required String user,
      required String password}) async {
    final changed = kind != GpodderSync.kind ||
        server.trim() != GpodderSync.server ||
        user.trim() != GpodderSync.user;
    await _putConfig({
      'kind': kind.name,
      'server': server.trim(),
      'user': user.trim(),
      if (changed) ..._freshState(),
      if (!configured || changed) 'auto': true,
    });
    await SecureCredentials.setNested(prefsKey, 'password', password);
    if (kind == GpodderKind.gpodderNet) {
      final api = _api();
      try {
        await api.registerDevice();
      } catch (e) {
        printERROR('gpodder device: $e');
      } finally {
        api.close();
      }
    }
  }

  static Map<String, dynamic> _freshState() => {
        'subsSince': 0,
        'actionsSince': 0,
        'followed': null,
        'pendingFollow': <String>[],
        'sentAt': 0,
        'pendingPlayed': <String>[],
      };

  static Future<void> setAutoSync(bool on) => _putConfig({'auto': on});

  /// Forgets the account (and what was synced with it); shows and episodes
  /// stay as they are.
  static Future<void> forget() async {
    final keep = _config['device'];
    await _prefs?.put(prefsKey, {if (keep != null) 'device': keep});
    await SecureCredentials.setNested(prefsKey, 'password', null);
    lastSyncAt.value = 0;
    lastError.value = '';
  }

  /// Syncs when auto-sync is on and the last try wasn't just now.
  /// [leaving]: the app is going to the background.
  static void maybeAutoSync({bool leaving = false}) {
    if (!autoSync || !configured) return;
    final now = clock().millisecondsSinceEpoch;
    if (!autoSyncDue(
        lastAttemptMs: _lastAttemptMs,
        nowMs: now,
        gap: leaving ? autoSyncLeavingGap : autoSyncGap)) {
      return;
    }
    unawaited(syncNow());
  }

  /// Syncs now; one already running is joined.
  static Future<GpodderOutcome> syncNow() =>
      _running ??= _sync().whenComplete(() => _running = null);

  static Future<GpodderOutcome> _sync() async {
    if (!configured) return const GpodderOutcome(error: GpodderError.auth);
    // Riff still starting (its podcast boxes not open yet): next time.
    if (!Hive.isBoxOpen('PodcastSubs')) return const GpodderOutcome();
    final started = clock();
    _lastAttemptMs = started.millisecondsSinceEpoch;
    syncing.value = true;
    final api = _api();
    GpodderOutcome outcome;
    try {
      final shows = await _syncShows(api);
      final episodes = await _syncEpisodes(api, started);
      outcome = GpodderOutcome(
        followed: shows.followed,
        unfollowed: shows.unfollowed,
        episodes: episodes.applied,
        sent: shows.sent + episodes.sent,
      );
    } catch (e) {
      printERROR('gpodder sync failed: $e');
      outcome = GpodderOutcome(error: gpodderErrorOf(e));
    } finally {
      api.close();
      syncing.value = false;
    }
    lastSyncAt.value = clock().millisecondsSinceEpoch;
    lastError.value = outcome.error?.name ?? '';
    await _putConfig(
        {'lastSyncAt': lastSyncAt.value, 'lastError': lastError.value});
    return outcome;
  }

  // ── Followed shows ─────────────────────────────────────────────────

  static Set<String> _followedHere() => {
        for (final s in PodcastService.subscriptions)
          if ('${s['feedUrl'] ?? ''}'.isNotEmpty) '${s['feedUrl']}'
      };

  static Future<({int followed, int unfollowed, int sent})> _syncShows(
      GpodderApi api) async {
    final c = _config;
    final since = _int(c['subsSince']) ?? 0;
    final then = c['followed'] is List ? _strings(c['followed']).toSet() : null;
    final here = _followedHere();
    // What this phone changed since the last sync (nothing to unfollow the
    // first time: both lists are joined).
    final added = then == null ? here : here.difference(then);
    final removed = then == null ? <String>{} : then.difference(here);

    final remote = await api.subscriptions(since);
    final remoteAdd = remote.add.toSet();
    final remoteRemove = remote.remove.toSet();

    var followed = 0;
    var unfollowed = 0;
    final waiting = <String>{};
    for (final feed in {..._strings(c['pendingFollow']), ...remoteAdd}) {
      if (removed.contains(feed) || remoteRemove.contains(feed)) continue;
      if (_followedHere().contains(feed)) continue;
      final show = await feedInfo(feed);
      // Can't be read now: tried again next time.
      if (show == null) {
        waiting.add(feed);
        continue;
      }
      await PodcastService.subscribe(
          {...show, 'feedUrl': show['feedUrl'] ?? feed});
      followed++;
    }
    for (final feed in remoteRemove) {
      if (added.contains(feed) || !here.contains(feed)) continue;
      await PodcastService.unsubscribe(feed);
      unfollowed++;
    }

    // This phone's changes go up (not what the server has already).
    final up = added.difference(remoteAdd);
    final down = removed.difference(remoteRemove);
    var timestamp = remote.timestamp;
    if (up.isNotEmpty || down.isNotEmpty) {
      timestamp = await api.uploadSubscriptions(up, down) ?? timestamp;
    }
    await _putConfig({
      'subsSince': timestamp,
      'followed': _followedHere().toList(),
      'pendingFollow': waiting.toList(),
    });
    return (
      followed: followed,
      unfollowed: unfollowed,
      sent: up.length + down.length,
    );
  }

  // ── Episodes ───────────────────────────────────────────────────────

  static Box? _box(String name) => Hive.isBoxOpen(name) ? Hive.box(name) : null;

  /// Episodes this phone knows (in progress, played, in the Inbox), by id,
  /// as {id, title, artist, artUri, url, feedUrl, durationMs, …}.
  static Map<String, Map<String, dynamic>> _knownEpisodes() {
    final out = <String, Map<String, dynamic>>{};
    void addItem(String id, Map<String, dynamic> meta) {
      final url = '${meta['url'] ?? ''}';
      if (id.isEmpty || !url.startsWith('http')) return;
      out.putIfAbsent(id, () => meta);
    }

    Map<String, dynamic> fromItem(Map<String, dynamic> j) {
      final extras = j['extras'] is Map ? j['extras'] as Map : const {};
      return {
        'id': '${j['id'] ?? ''}',
        'title': j['title'],
        'artist': j['artist'],
        'artUri': j['artUri'],
        'url': extras['remoteUrl'] ?? extras['url'],
        'feedUrl': extras['feedUrl'],
        'guid': extras['guid'],
        'description': extras['description'],
        'durationMs': j['durationMs'],
      };
    }

    final progress = _box('PodcastProgress');
    if (progress != null) {
      for (final row in progress.values) {
        if (row is Map) addItem('${row['id'] ?? ''}', Map.from(row));
      }
    }
    for (final entry in PodcastHistory.all) {
      addItem(entry.id, fromItem(entry.episode));
    }
    final inbox = PodcastInboxCache.load(null)?.items ?? const [];
    for (final e in inbox) {
      addItem(e.id, {
        'id': e.id,
        'title': e.title,
        'artist': e.artist,
        'artUri': e.artUri?.toString(),
        'url': e.extras?['remoteUrl'] ?? e.extras?['url'],
        'feedUrl': e.extras?['feedUrl'],
        'guid': e.extras?['guid'],
        'description': e.extras?['description'],
        'durationMs': e.duration?.inMilliseconds,
      });
    }
    return out;
  }

  /// Riff's id for the episode an action names: by its guid, else the
  /// episode known by its address, else as the feed parser makes it.
  static String _idFor(GpodderAction a, Map<String, String> idByUrl) {
    if (a.guid != null) {
      return riffRssEpisodeId(guid: a.guid, enclosureUrl: a.episode);
    }
    return idByUrl[a.episode] ?? riffRssEpisodeId(enclosureUrl: a.episode);
  }

  /// When this phone last changed the episode [id] (played or its place),
  /// or null.
  static int? _changedAt(String id) {
    final played = _box('PodcastPlayed')?.get(id);
    if (played is int) return played;
    final row = _box('PodcastProgress')?.get(id);
    return row is Map ? _int(row['updatedAt']) : null;
  }

  static Future<({int applied, int sent})> _syncEpisodes(
      GpodderApi api, DateTime started) async {
    final c = _config;
    final since = _int(c['actionsSince']) ?? 0;
    final sentAt = _int(c['sentAt']) ?? 0;
    final known = _knownEpisodes();
    final idByUrl = {
      for (final e in known.entries) '${e.value['url']}': e.key,
    };

    // The server's: the newest action for each episode.
    final remote = await api.episodeActions(since);
    final newest = <String, GpodderAction>{};
    for (final a in remote.actions) {
      if (a.action != 'play' || !a.episode.startsWith('http')) continue;
      final id = _idFor(a, idByUrl);
      final before = newest[id];
      if (before == null || a.at.isAfter(before.at)) newest[id] = a;
    }
    final applied = <String>{};
    final feeds = <String, List<Map<String, dynamic>>>{};
    for (final e in newest.entries) {
      if (await _apply(e.key, e.value, known, feeds)) applied.add(e.key);
    }

    // This phone's since the last sync (not what just came from the server).
    final actions = <GpodderAction>[];
    final progress = _box('PodcastProgress');
    if (progress != null) {
      for (final row in progress.values) {
        if (row is! Map) continue;
        final id = '${row['id'] ?? ''}';
        final at = _int(row['updatedAt']) ?? 0;
        if (at <= sentAt || applied.contains(id)) continue;
        final action = _action(Map.from(row),
            at: at,
            position: (_int(row['positionMs']) ?? 0) ~/ 1000,
            total: (_int(row['durationMs']) ?? 0) ~/ 1000);
        if (action != null) actions.add(action);
      }
    }
    // Played ones this phone can't place yet (not known here) wait for a
    // later sync instead of being passed by sentAt.
    final before = c['pendingPlayed'];
    final pending = {if (before is List) ...before.map((e) => '$e')};
    final waiting = <String>[];
    final played = _box('PodcastPlayed');
    if (played != null) {
      for (final key in played.keys) {
        final id = '$key';
        final at = _int(played.get(key)) ?? 0;
        if (applied.contains(id)) continue;
        if (at <= sentAt && !pending.contains(id)) continue;
        var meta = known[id];
        if (meta == null) {
          waiting.add(id);
          continue;
        }
        var total = (_int(meta['durationMs']) ?? 0) ~/ 1000;
        final feed = '${meta['feedUrl'] ?? ''}';
        if (total <= 0 && feed.startsWith('http')) {
          // Its length from the show's feed (each feed read once a sync).
          final fromFeed = await _fromFeed(feed, id, feeds);
          final ms = _int(fromFeed?['durationMs']) ?? 0;
          if (ms > 0) {
            meta = {...meta, 'durationMs': ms};
            total = ms ~/ 1000;
          }
        }
        // Played to its end; with no length known, 1 of 1 still reads as
        // played (position ≥ total) on the other side.
        if (total <= 0) total = 1;
        final action = _action(meta, at: at, position: total, total: total);
        if (action != null) actions.add(action);
      }
    }
    var timestamp = remote.timestamp;
    for (var i = 0; i < actions.length; i += _batch) {
      final part = actions.sublist(i, min(i + _batch, actions.length));
      timestamp = await api.uploadActions(part) ?? timestamp;
    }
    await _putConfig({
      'actionsSince': timestamp,
      'sentAt': started.millisecondsSinceEpoch,
      'pendingPlayed': waiting,
    });
    return (applied: applied.length, sent: actions.length);
  }

  static GpodderAction? _action(Map meta,
      {required int at, required int position, required int total}) {
    final url = '${meta['url'] ?? ''}';
    final feed = '${meta['feedUrl'] ?? ''}';
    if (!url.startsWith('http') || !feed.startsWith('http')) return null;
    final guid = meta['guid'];
    return GpodderAction(
      podcast: feed,
      episode: url,
      guid: guid is String && guid.isNotEmpty ? guid : null,
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      position: position,
      total: total,
    );
  }

  /// Takes in the server's newest action for the episode [id], when it's
  /// newer than this phone's. True when it changed something.
  static Future<bool> _apply(
      String id,
      GpodderAction a,
      Map<String, Map<String, dynamic>> known,
      Map<String, List<Map<String, dynamic>>> feeds) async {
    final progress = _box('PodcastProgress');
    final played = _box('PodcastPlayed');
    if (progress == null || played == null) return false;
    final at = a.at.millisecondsSinceEpoch;
    final mine = _changedAt(id);
    if (mine != null && mine >= at) return false;
    if (a.finished) {
      await progress.delete(id);
      await played.put(id, at);
      if (Get.isRegistered<PodcastQueueController>()) {
        Get.find<PodcastQueueController>().removeById(id);
      }
      return true;
    }
    // Barely started, as the player keeps no place for it either.
    if (a.position < 15) return false;
    final meta = known[id] ?? await _fromFeed(a.podcast, id, feeds);
    if (meta == null) return false;
    final durationMs =
        a.total > 0 ? a.total * 1000 : _int(meta['durationMs']) ?? 0;
    if (durationMs <= 0) return false;
    await played.delete(id);
    await progress.put(id, {
      'id': id,
      'title': meta['title'],
      'artist': meta['artist'],
      'artUri': meta['artUri'],
      'url': meta['url'] ?? a.episode,
      'feedUrl': meta['feedUrl'] ?? a.podcast,
      if (meta['description'] != null) 'description': meta['description'],
      'positionMs': a.position * 1000,
      'durationMs': durationMs,
      'updatedAt': at,
    });
    return true;
  }

  /// The episode [id] as its show's feed lists it (each feed read once a
  /// sync), or null.
  static Future<Map<String, dynamic>?> _fromFeed(String feed, String id,
      Map<String, List<Map<String, dynamic>>> feeds) async {
    var episodes = feeds[feed];
    if (episodes == null) {
      final show = PodcastService.subscriptions
          .firstWhereOrNull((s) => s['feedUrl'] == feed);
      try {
        episodes = await feedEpisodes(
            feed, '${show?['title'] ?? ''}', '${show?['artwork'] ?? ''}');
      } catch (e) {
        printERROR('gpodder feed $feed: $e');
        episodes = const [];
      }
      feeds[feed] = episodes;
    }
    final ep = episodes.firstWhereOrNull((e) => e['id'] == id);
    if (ep == null) return null;
    final show = PodcastService.subscriptions
        .firstWhereOrNull((s) => s['feedUrl'] == feed);
    final seconds = _int(ep['durationSec']) ?? 0;
    return {
      'id': id,
      'title': ep['title'],
      'artist': show?['title'] ?? ep['podcast'],
      'artUri': ep['artwork'],
      'url': ep['url'],
      'feedUrl': feed,
      'description': ep['description'],
      'durationMs': seconds * 1000,
    };
  }
}
