/// WebDAV sync: reads each collection file from the listener's `Riff/`
/// folder, merges it with what the app holds (docs/sync-format.md), takes
/// in the result and writes the file back when the merge changed it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/helper.dart';
import '/utils/secure_credentials.dart';
import 'sync_collections.dart';
import 'sync_merge.dart';
import 'webdav_client.dart';

/// Folder on the server that holds everything.
const syncRoot = 'Riff';

/// Automatic syncs on app start and on coming back from the background run
/// at most this often.
const autoSyncGap = Duration(minutes: 5);

/// Going to the background syncs unless a sync ran this recently (it hands
/// this session's changes over, so it waits less).
const autoSyncLeavingGap = Duration(seconds: 30);

/// Whether an automatic sync may run now.
bool autoSyncDue(
        {required int? lastAttemptMs,
        required int nowMs,
        Duration gap = autoSyncGap}) =>
    lastAttemptMs == null ||
    nowMs - lastAttemptMs >= gap.inMilliseconds ||
    nowMs < lastAttemptMs;

/// How a sync went.
class SyncOutcome {
  const SyncOutcome({this.error, this.received = 0, this.sent = 0});

  /// Null when everything synced.
  final WebDavError? error;

  /// Records taken in from the server.
  final int received;

  /// Files written to the server.
  final int sent;

  bool get ok => error == null;
}

/// The WebDAV account and auto-sync switch live in AppPrefs `webdavSync`;
/// the password is in secure storage (`webdavSync.password`). What was
/// last synced per collection is in the `SyncLedger` box.
class WebDavSyncService {
  WebDavSyncService._();

  static const prefsKey = 'webdavSync';
  static const ledgerBox = 'SyncLedger';

  static final syncing = false.obs;

  /// Last finished sync (ms) and its error ('' when fine), for the page.
  static final lastSyncAt = 0.obs;
  static final lastError = ''.obs;

  static int? _lastAttemptMs;
  static Future<SyncOutcome>? _running;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static Map<String, dynamic> get _config {
    final v = _prefs?.get(prefsKey);
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  static String get serverUrl => '${_config['url'] ?? ''}';
  static String get user => '${_config['user'] ?? ''}';
  static String get password =>
      SecureCredentials.nested(prefsKey, 'password') ?? '';
  static bool get autoSync => _config['auto'] == true;
  static bool get configured => serverUrl.isNotEmpty && user.isNotEmpty;

  /// Load the last result for the settings page.
  static void loadStatus() {
    final c = _config;
    lastSyncAt.value = c['lastSyncAt'] is int ? c['lastSyncAt'] as int : 0;
    lastError.value = '${c['lastError'] ?? ''}';
  }

  static Future<void> _putConfig(Map<String, dynamic> changes) async {
    await _prefs?.put(prefsKey, {..._config, ...changes});
  }

  /// This install's id for the format's tie-break (16 hex digits).
  static String get deviceId {
    final prefs = _prefs;
    final existing = prefs?.get('syncDeviceId');
    if (existing is String && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final id = List.generate(8, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    prefs?.put('syncDeviceId', id);
    return id;
  }

  /// Save the account. A different server or user starts afresh: what was
  /// synced with the old one says nothing about the new one.
  static Future<void> saveAccount(
      {required String url,
      required String user,
      required String password}) async {
    final u = url.trim();
    final changed = u != serverUrl || user.trim() != WebDavSyncService.user;
    await _putConfig({'url': u, 'user': user.trim()});
    await SecureCredentials.setNested(prefsKey, 'password', password);
    if (changed) await _clearLedger();
  }

  static Future<void> setAutoSync(bool on) => _putConfig({'auto': on});

  /// Forget the account (and what was synced with it). Data stays.
  static Future<void> forget() async {
    await _prefs?.delete(prefsKey);
    await SecureCredentials.setNested(prefsKey, 'password', null);
    await _clearLedger();
    lastSyncAt.value = 0;
    lastError.value = '';
  }

  static Future<Box> _ledger() async => Hive.isBoxOpen(ledgerBox)
      ? Hive.box(ledgerBox)
      : await Hive.openBox(ledgerBox);

  static Future<void> _clearLedger() async => (await _ledger()).clear();

  /// Tests swap in a client on a fake server.
  @visibleForTesting
  static WebDavClient Function(String url, String user, String password)?
      clientFactory;

  static WebDavClient _client(String url, String user, String password) =>
      clientFactory?.call(url, user, password) ??
      WebDavClient(baseUrl: url, user: user, password: password);

  /// Check a URL and account before saving it. Null when it works.
  static Future<WebDavError?> testConnection(
      String url, String user, String password) async {
    if (!validWebDavBase(url)) return WebDavError.notFound;
    try {
      await _client(url, user, password).check();
      return null;
    } on WebDavException catch (e) {
      return e.error;
    } catch (_) {
      return WebDavError.network;
    }
  }

  /// Sync when auto-sync is on and the last try wasn't just now.
  /// [leaving]: the app is going to the background.
  static void maybeAutoSync({bool leaving = false}) {
    if (!autoSync || !configured) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!autoSyncDue(
        lastAttemptMs: _lastAttemptMs,
        nowMs: now,
        gap: leaving ? autoSyncLeavingGap : autoSyncGap)) {
      return;
    }
    unawaited(syncNow());
  }

  /// Sync everything now. A sync already running is joined, not repeated.
  static Future<SyncOutcome> syncNow() {
    return _running ??= _sync().whenComplete(() => _running = null);
  }

  static Future<SyncOutcome> _sync() async {
    if (!configured) return const SyncOutcome(error: WebDavError.auth);
    _lastAttemptMs = DateTime.now().millisecondsSinceEpoch;
    syncing.value = true;
    var outcome = const SyncOutcome();
    try {
      outcome = await _syncAll(_client(serverUrl, user, password));
    } on WebDavException catch (e) {
      outcome = SyncOutcome(error: e.error);
    } catch (e) {
      printERROR('WebDAV sync failed: $e');
      outcome = const SyncOutcome(error: WebDavError.server);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    lastError.value = outcome.error?.name ?? '';
    if (outcome.ok) lastSyncAt.value = now;
    await _putConfig({
      'lastError': lastError.value,
      if (outcome.ok) 'lastSyncAt': now,
    });
    syncing.value = false;
    return outcome;
  }

  static Future<SyncOutcome> _syncAll(WebDavClient dav) async {
    final device = deviceId;
    await dav.ensureFolder('$syncRoot/podcasts/');
    await dav.ensureFolder('$syncRoot/library/');

    const manifestPath = '$syncRoot/manifest.json';
    final manifest = await dav.read(manifestPath);
    Map<String, dynamic> manifestExtra = {};
    if (manifest != null) {
      final Object? j;
      try {
        j = jsonDecode(manifest.body);
      } catch (_) {
        throw const WebDavException(WebDavError.badFile);
      }
      if (j is! Map) throw const WebDavException(WebDavError.badFile);
      final v = j['version'];
      if (v is int && !syncVersionSupported(v)) {
        throw const WebDavException(WebDavError.tooNew);
      }
      manifestExtra = Map<String, dynamic>.from(j);
    }

    var received = 0, sent = 0;
    WebDavError? firstError;
    for (final c in syncCollections) {
      try {
        final r = await _syncCollection(dav, c, device);
        received += r.received;
        sent += r.sent;
      } on WebDavException catch (e) {
        // A bad file or a lost race on one collection doesn't stop the
        // others; a dead connection or a wrong password does.
        if (e.error == WebDavError.auth || e.error == WebDavError.network) {
          rethrow;
        }
        printERROR('Sync of ${c.name} failed: $e');
        firstError ??= e.error;
      }
    }

    if (sent > 0 || manifest == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await dav.write(
          manifestPath,
          const JsonEncoder.withIndent(' ').convert({
            ...manifestExtra,
            'format': syncFormatName,
            'version': syncFormatVersion,
            'updatedAt': now,
            'device': device,
          }),
          contentType: 'application/json; charset=utf-8');
    }
    return SyncOutcome(error: firstError, received: received, sent: sent);
  }

  static Future<({int received, int sent})> _syncCollection(
      WebDavClient dav, SyncCollection c, String device) async {
    final path = '$syncRoot/${c.path}';
    final ledgerStore = await _ledger();
    for (var attempt = 0;; attempt++) {
      final file = await dav.read(path);
      DecodedFile remote = (records: const {}, extra: const {});
      if (file != null && file.body.trim().isNotEmpty) {
        try {
          remote = c.decode(file.body);
        } on FormatException catch (e) {
          throw WebDavException(
              e.message == 'Newer format'
                  ? WebDavError.tooNew
                  : WebDavError.badFile,
              message: c.name);
        }
      }
      final adopted = c.adopt(remote.records, device);
      final remoteRecords = adopted ?? remote.records;

      final now = DateTime.now().millisecondsSinceEpoch;
      final rawLedger = ledgerStore.get(c.name);
      final ledger = <String, LedgerEntry>{
        if (rawLedger is Map)
          for (final e in rawLedger.entries)
            if (LedgerEntry.fromJson(e.value) case final l?) '${e.key}': l
      };
      final local = localRecords(
          items: await c.readLocal(),
          ledger: ledger,
          device: device,
          nowMs: now);
      final merge = mergeRecords(local, remoteRecords, nowMs: now);
      final changes = merge.localChanges(local);
      await c.apply({for (final id in changes) id: merge.winners[id]!});
      // Remember what the app now holds before writing: if the write fails,
      // what was taken in mustn't look like a local edit next time.
      final held = await c.readLocal();
      await ledgerStore.put(c.name, {
        for (final e in nextLedger(merge.winners, held, nowMs: now).entries)
          e.key: e.value.toJson()
      });

      var sent = 0;
      if (merge.remoteChanged || adopted != null || file == null) {
        try {
          await dav.write(
              path,
              c.encode(merge.merged,
                  extra: remote.extra, nowMs: now, device: device),
              ifMatch: file?.etag,
              create: file == null,
              contentType: c.contentType);
          sent = 1;
        } on WebDavException catch (e) {
          // Someone wrote in between: read, merge and try again.
          if (e.error == WebDavError.conflict && attempt < 3) continue;
          rethrow;
        }
      }
      return (received: changes.length, sent: sent);
    }
  }
}
