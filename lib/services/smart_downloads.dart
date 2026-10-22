/// Smart downloads, as YouTube Music's: the songs you play most stay
/// downloaded, so there's always music to play offline. Once a day, on
/// Wi-Fi, Riff downloads the ones it hasn't got yet ([smartPicks]: music
/// you've heard through at least twice in the last three months, most
/// heard first, up to [SmartDownloads.count]) and removes again the ones
/// it downloaded that you've stopped playing, unless you've liked them or
/// put them in a playlist. One you delete yourself isn't downloaded again.
/// Off by default; turning it off keeps what's downloaded.
library;

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';

import '/models/media_Item_builder.dart';
import '/models/media_item_extras.dart';
import '/native_bindings/andrid_utils.dart' show SDKInt;
import '/ui/player/player_controller.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import 'ban_service.dart';
import 'downloader.dart';
import 'network_kind.dart';
import 'offline_playback.dart';
import 'stats_service.dart';

/// What a look by Smart downloads came to.
enum SmartDownloadsRun {
  /// Switched off.
  off,

  /// It looked not long ago, or can't now (no permission to the download
  /// folder yet): later.
  notDue,

  /// On mobile data: once on Wi-Fi.
  waitingForWifi,

  /// No song played often enough yet.
  nothingYet,

  /// The songs are all downloaded.
  upToDate,

  /// Downloading [SmartDownloads.started] songs.
  started,
}

class SmartDownloads {
  SmartDownloads._();

  /// AppPrefs keys.
  static const key = 'smartDownloads';
  static const countKey = 'smartDownloadsCount';
  static const lastRunKey = 'smartDownloadsLastRun';

  /// The songs it downloaded (seen downloaded).
  static const keptKey = 'smartDownloadsKept';

  /// The songs it set downloading, not seen downloaded yet.
  static const pendingKey = 'smartDownloadsPending';

  /// Songs it downloaded that you deleted: not downloaded again.
  static const declinedKey = 'smartDownloadsDeclined';

  /// How many songs it keeps: the choices, and the first.
  static const counts = [25, 50, 100];
  static const defaultCount = 50;

  /// How long it leaves between looks.
  static const every = Duration(hours: 20);

  /// Only songs heard within this long count.
  static const window = Duration(days: 90);

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static int _countOf(Object? raw) =>
      raw is int && counts.contains(raw) ? raw : defaultCount;

  /// Whether the song with this id is one it set downloading (they go on
  /// Wi-Fi only).
  static bool isPending(String id) {
    if (!enabled.value) return false;
    final pending = _prefs?.get(pendingKey);
    return pending is List && pending.contains(id);
  }

  /// For Settings.
  static final enabled = RxBool(_prefs?.get(key) == true);
  static final count = RxInt(_countOf(_prefs?.get(countKey)));

  /// How many songs the last look set downloading.
  static int started = 0;

  /// Reads the settings again (tests, after AppPrefs opens).
  @visibleForTesting
  static void reload() {
    enabled.value = _prefs?.get(key) == true;
    count.value = _countOf(_prefs?.get(countKey));
  }

  /// Switches it on (a look now: [run]) or off.
  static Future<SmartDownloadsRun> set(bool on) async {
    enabled.value = on;
    await _prefs?.put(key, on);
    if (!on) {
      // Nothing it set downloading waits for Wi-Fi any more.
      await _prefs?.delete(pendingKey);
      return SmartDownloadsRun.off;
    }
    return run(force: true);
  }

  /// How many songs it keeps; it looks again at once.
  static Future<SmartDownloadsRun> setCount(int n) async {
    if (!counts.contains(n)) return SmartDownloadsRun.notDue;
    count.value = n;
    await _prefs?.put(countKey, n);
    return run(force: true);
  }

  /// All downloads removed at once (Settings): what it downloaded, set
  /// downloading and was told not to download again, forgotten.
  static Future<void> forgetDownloads() async =>
      _prefs?.deleteAll(const [keptKey, pendingKey, declinedKey]);

  /// Songs you download yourself are yours: never removed when they drop
  /// out of your most played, nor held for Wi-Fi as its own are.
  static Future<void> claim(Iterable<String> ids) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final mine = ids.toSet();
    if (mine.isEmpty) return;
    final kept = _ids(prefs.get(keptKey));
    final pending = _ids(prefs.get(pendingKey));
    if (!kept.any(mine.contains) && !pending.any(mine.contains)) return;
    await prefs.putAll({
      keptKey: kept.where((id) => !mine.contains(id)).toList(),
      pendingKey: pending.where((id) => !mine.contains(id)).toList(),
    });
  }

  static Timer? _timer;

  /// Looks a minute after Riff starts, then every hour it stays open (a
  /// look comes to something once a day at most: [every]).
  static void start() {
    _timer ??= Timer.periodic(const Duration(hours: 1), (_) => run());
    Future<void>.delayed(const Duration(minutes: 1), run);
  }

  /// Whether the connection costs data; tests set it.
  @visibleForTesting
  static Future<bool> Function() metered = NetworkKind.isMetered;

  /// Whether downloads can go to the download folder without asking for a
  /// permission (a look of its own never asks); tests set it.
  @visibleForTesting
  static Future<bool> Function() storageReady = _storageReady;

  /// Sets [songs] downloading; tests set it.
  @visibleForTesting
  static Future<void> Function(List<MediaItem> songs) queue = _queue;

  /// Deletes the download of the song with this id; tests set it.
  @visibleForTesting
  static Future<void> Function(String id) removeDownload = _removeDownload;

  /// The song playing now; tests set it.
  @visibleForTesting
  static String? Function() playingId = _playingId;

  @visibleForTesting
  static int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  static bool _running = false;

  /// Downloads the songs you play most that aren't yet and removes the
  /// ones it downloaded you've stopped playing; at most once in [every]
  /// unless [force]d (Settings).
  static Future<SmartDownloadsRun> run({bool force = false}) async {
    final prefs = _prefs;
    if (!enabled.value || prefs == null) return SmartDownloadsRun.off;
    if (_running) return SmartDownloadsRun.notDue;
    final at = now();
    final last = prefs.get(lastRunKey);
    if (!force && last is int && at - last < every.inMilliseconds) {
      return SmartDownloadsRun.notDue;
    }
    if (!Hive.isBoxOpen('SongDownloads') || !Hive.isBoxOpen('SongStats')) {
      return SmartDownloadsRun.notDue;
    }
    _running = true;
    try {
      if (await metered()) return SmartDownloadsRun.waitingForWifi;
      if (!force && !await storageReady()) return SmartDownloadsRun.notDue;
      return await _look(prefs, at);
    } catch (e) {
      printERROR('Smart downloads: $e');
      return SmartDownloadsRun.notDue;
    } finally {
      _running = false;
    }
  }

  static Future<SmartDownloadsRun> _look(Box prefs, int at) async {
    final downloads = Hive.box('SongDownloads');
    bool downloaded(String id) => downloads.containsKey(id);

    final kept = _ids(prefs.get(keptKey));
    final declined = _ids(prefs.get(declinedKey));
    // Set downloading last time, and downloaded since.
    kept.addAll(_ids(prefs.get(pendingKey)).where(downloaded));
    // Downloaded, then gone: you deleted it.
    for (final id in kept.where((id) => !downloaded(id)).toList()) {
      kept.remove(id);
      declined.add(id);
    }

    final picks = topSongsToPlay(smartPicks(
      Hive.box('SongStats').toMap(),
      count: count.value,
      nowMs: at,
      leaveOut: declined,
      banned: BanService.isBanned,
    )).where((s) => s.streamSource == null).toList();

    // No longer among them: removed, unless you keep it some other way.
    final picked = {for (final s in picks) s.id};
    final dropped = kept.where((id) => !picked.contains(id)).toList();
    if (dropped.isNotEmpty) {
      final yours = await _yourSongs();
      final playing = playingId();
      for (final id in dropped) {
        if (yours.contains(id) || id == playing) continue;
        await removeDownload(id);
        kept.remove(id);
      }
    }

    final missing = [
      for (final s in picks)
        if (!downloaded(s.id)) s
    ];
    await prefs.putAll({
      keptKey: kept.toList(),
      pendingKey: [for (final s in missing) s.id],
      declinedKey: declined.toList(),
      lastRunKey: at,
    });
    started = missing.length;
    if (missing.isNotEmpty) await queue(missing);
    if (picks.isEmpty) return SmartDownloadsRun.nothingYet;
    return missing.isEmpty
        ? SmartDownloadsRun.upToDate
        : SmartDownloadsRun.started;
  }

  static Set<String> _ids(Object? raw) =>
      raw is List ? raw.map((e) => '$e').toSet() : <String>{};

  /// Songs you keep yourself: liked, or in one of your own playlists (not
  /// Riff's mixes, nor YouTube's or Piped's playlists).
  static Future<Set<String>> _yourSongs() async {
    final ids = <String>{
      if (Hive.isBoxOpen('LIBFAV')) ...Hive.box('LIBFAV').keys.map((k) => '$k'),
    };
    if (!Hive.isBoxOpen('LibraryPlaylists')) return ids;
    for (final raw in Hive.box('LibraryPlaylists').values.toList()) {
      if (raw is! Map) continue;
      final id = '${raw['playlistId'] ?? ''}';
      if (id.isEmpty ||
          id.startsWith('RIFF_') ||
          raw['isCloudPlaylist'] != false ||
          raw['isPipedPlaylist'] == true) {
        continue;
      }
      try {
        final Box box;
        if (Hive.isBoxOpen(id)) {
          box = Hive.box(id);
        } else if (await Hive.boxExists(id)) {
          box = await Hive.openBox(id);
        } else {
          continue;
        }
        for (final song in box.values) {
          if (song is Map && song['videoId'] != null) {
            ids.add('${song['videoId']}');
          }
        }
      } catch (_) {
        // Can't be read: none of its songs are removed.
        return {...ids, ...Hive.box('SongDownloads').keys.map((k) => '$k')};
      }
    }
    return ids;
  }

  static Future<bool> _storageReady() async {
    if (!Get.isRegistered<SettingsScreenController>()) return false;
    if (Get.find<SettingsScreenController>().isCurrentPathsupportDownDir ||
        GetPlatform.isDesktop) {
      return true;
    }
    return SDKInt.Companion.getSDKInt() < 30
        ? Permission.storage.isGranted
        : Permission.manageExternalStorage.isGranted;
  }

  static Future<void> _queue(List<MediaItem> songs) async {
    if (!Get.isRegistered<Downloader>()) return;
    final downloader = Get.find<Downloader>();
    final waiting = downloader.songQueue.toSet();
    final fresh = songs.where((s) => !waiting.contains(s)).toList();
    if (fresh.isEmpty) return;
    // Picked from what you play, they aren't a sign of taste of their own.
    unawaited(downloader.download(null, songList: fresh, signal: false));
  }

  static Future<void> _removeDownload(String id) async {
    final box = Hive.box('SongDownloads');
    final raw = box.get(id);
    final path = raw is Map ? '${raw['url'] ?? ''}' : '';
    // Another download in the same file (a song of the same title and
    // artist, saved before downloads were named apart): only the entry.
    final shared = path.isNotEmpty &&
        box.keys.any((k) =>
            k != id && box.get(k) is Map && '${box.get(k)['url']}' == path);
    if (shared) {
      await box.delete(id);
      return;
    }
    if (raw is Map && Get.isRegistered<LibrarySongsController>()) {
      // Its file, its cover and its place in Songs.
      await Get.find<LibrarySongsController>()
          .removeSong(MediaItemBuilder.fromJson(raw), true, url: path);
    } else if (path.isNotEmpty) {
      try {
        await File(path.startsWith('file://') ? path.substring(7) : path)
            .delete();
      } catch (_) {}
    }
    await box.delete(id);
  }

  static String? _playingId() => Get.isRegistered<PlayerController>()
      ? Get.find<PlayerController>().currentSong.value?.id
      : null;
}

bool _noBans(String id) => false;

int _int(Object? v) => v is num ? v.toInt() : 0;

/// The songs Smart downloads keeps, most heard first, as
/// [StatsService.topSongs] lists them: YouTube songs you've heard through
/// (played and not skipped) at least twice, last within [window] before
/// [nowMs], at most [count]; [leaveOut] and [banned] ones aside. [stats]
/// is SongStats' entries.
@visibleForTesting
List<Map<String, dynamic>> smartPicks(Map<dynamic, dynamic> stats,
    {required int count,
    required int nowMs,
    Duration window = SmartDownloads.window,
    Set<String> leaveOut = const {},
    bool Function(String id) banned = _noBans}) {
  final since = nowMs - window.inMilliseconds;
  final picks = <Map<String, dynamic>>[];
  stats.forEach((key, value) {
    final id = '$key';
    if (value is! Map ||
        '${value['kind'] ?? ''}'.isNotEmpty ||
        !OfflinePlayback.playsFromYouTube(id) ||
        leaveOut.contains(id) ||
        banned(id)) {
      return;
    }
    final heard = _int(value['plays']) - _int(value['skips']);
    final last = _int(value['lastPlayed']);
    if (heard < 2 || last < since) return;
    picks.add({
      'id': id,
      'title': value['title'] ?? '',
      'artist': value['artist'] ?? '',
      'kind': '',
      'heard': heard,
      'lastPlayed': last,
    });
  });
  picks.sort((a, b) {
    final byHeard = (b['heard'] as int).compareTo(a['heard'] as int);
    return byHeard != 0
        ? byHeard
        : (b['lastPlayed'] as int).compareTo(a['lastPlayed'] as int);
  });
  return picks.take(count).toList();
}
