import '/ui/player/long_form_queue.dart';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '/services/pending_file_deletes.dart';
import '/services/download_notice.dart';

/// A download taken out with Undo on offer ([PodcastDownloadService.takeOut]):
/// its stored entry and its file.
typedef PodcastDownloadRemoval = ({String id, Object entry, String? path});

/// The pending-delete key of an episode's file ([markPendingFiles]).
String podcastDownloadPendingKey(String id) => 'podcast:$id';

/// The episode id in a pending-delete key, or null for another owner's.
String? podcastDownloadIdFromPendingKey(String key) =>
    key.startsWith('podcast:') ? key.substring('podcast:'.length) : null;

/// Downloads podcast episodes (direct enclosure URLs) to local storage so they
/// can be played offline. Records live in the `PodcastDownloads` Hive box,
/// keyed by episode id. Values are either a legacy absolute path [String] or a
/// metadata [Map] with at least `path`. Playback prefers the local copy via
/// MyAudioHandler.checkNGetUrl.
class PodcastDownloadService {
  PodcastDownloadService._();

  // No timeouts used to mean a download to a host that never answered
  // stayed "started" forever. receiveTimeout bounds the wait for the
  // response headers only, not the length of the transfer.
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
  ));

  @visibleForTesting
  static BaseOptions get httpOptions => _dio.options;
  static final Set<String> _downloadedIds = {};
  static bool _cacheWarmed = false;

  static Box get _box => Hive.box('PodcastDownloads');

  static String? _pathFrom(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is Map && value['path'] is String) {
      final p = value['path'] as String;
      if (p.isNotEmpty) return p;
    }
    return null;
  }

  static void _warmCache() {
    if (_cacheWarmed || !Hive.isBoxOpen('PodcastDownloads')) return;
    _cacheWarmed = true;
    for (final key in _box.keys) {
      final p = _pathFrom(_box.get(key));
      if (p != null) {
        _downloadedIds.add(key.toString());
      }
    }
  }

  /// Fast path for UI (long-press sheet) — memory only, no disk I/O.
  static bool isDownloaded(String id) {
    _warmCache();
    if (_downloadedIds.contains(id)) return true;
    // Late write after warm — peek Hive once.
    if (Hive.isBoxOpen('PodcastDownloads') && _box.containsKey(id)) {
      if (_pathFrom(_box.get(id)) != null) {
        _downloadedIds.add(id);
        return true;
      }
    }
    return false;
  }

  /// Absolute local path if the episode is downloaded and the file still
  /// exists, else null. May touch the filesystem (playback / cleanup).
  static String? localPath(String id) {
    if (!Hive.isBoxOpen('PodcastDownloads')) return null;
    _warmCache();
    if (!_downloadedIds.contains(id) && _box.containsKey(id)) {
      _downloadedIds.add(id);
    }
    if (!_downloadedIds.contains(id)) return null;
    final p = _pathFrom(_box.get(id));
    if (p != null && File(p).existsSync()) return p;
    // Stale Hive entry — drop it.
    _downloadedIds.remove(id);
    _box.delete(id);
    return null;
  }

  static Future<String> _dir() async {
    final base = (await getApplicationSupportDirectory()).path;
    final dir = Directory('$base/podcast_downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Downloads still running, by episode id.
  static final _inFlight = <String, Future<bool>>{};

  /// Download [episode]'s audio. Returns true on success (or if already
  /// downloaded). [onProgress] receives 0..1.
  ///
  /// Asking again while that episode is still downloading joins the
  /// running download: two at once wrote the same file, and the one that
  /// failed deleted the file the other was finishing.
  static Future<bool> download(MediaItem episode,
      {void Function(double)? onProgress}) {
    final running = _inFlight[episode.id];
    if (running != null) return running;
    final job = _download(episode, onProgress: onProgress);
    _inFlight[episode.id] = job;
    return job.whenComplete(() {
      _inFlight.remove(episode.id);
      _noticeFinish(episode.id);
    });
  }

  /// In the downloads' notification: the episodes downloading, and how
  /// many have finished since it came up.
  static final _noticed = <String>{};
  static int _noticedDone = 0;
  static String _noticeText = '';

  static void _noticeStart(MediaItem episode) {
    _noticed.add(episode.id);
    _noticeText = episode.title;
    _noticeShow();
  }

  static void _noticeFinish(String id) {
    if (!_noticed.remove(id)) return;
    _noticedDone++;
    if (_noticed.isNotEmpty) return _noticeShow();
    _noticedDone = 0;
    DownloadNotice.end(DownloadNotice.episodes);
  }

  static void _noticeShow() => DownloadNotice.update(DownloadNotice.episodes,
      done: _noticedDone,
      total: _noticedDone + _noticed.length,
      text: _noticeText);

  static Future<bool> _download(MediaItem episode,
      {void Function(double)? onProgress}) async {
    final url = episode.extras?['url'] as String?;
    if (url == null || url.isEmpty) return false;
    if (isDownloaded(episode.id) && localPath(episode.id) != null) return true;
    _noticeStart(episode);
    try {
      final dir = await _dir();
      final safe = episode.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final path = '$dir/$safe${_ext(url)}';
      await _dio.download(url, path, onReceiveProgress: (rec, total) {
        if (total > 0 && onProgress != null) onProgress(rec / total);
      });
      await _box.put(episode.id, {
        'path': path,
        'id': episode.id,
        'title': episode.title,
        'artist': episode.artist,
        'artUri': episode.artUri?.toString(),
        'durationMs': episode.duration?.inMilliseconds,
        'url': url,
        'isPodcast': true,
        'feedUrl': episode.extras?['feedUrl'],
        'description': episodeNotes(episode),
        'date': episode.extras?['date'],
        'pubDateMs': episode.extras?['pubDateMs'],
        'chaptersUrl': episodeChaptersUrl(episode),
        'transcriptUrl': episode.extras?['transcriptUrl'],
        'transcriptType': episode.extras?['transcriptType'],
      });
      _downloadedIds.add(episode.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Takes the download of [id] out (its entry, so it no longer counts as
  /// downloaded) but keeps its file until [commitRemoval], so [restore]
  /// can bring it back (Undo). Null when it isn't downloaded.
  static Future<PodcastDownloadRemoval?> takeOut(String id) async {
    if (!Hive.isBoxOpen('PodcastDownloads')) return null;
    final Object? entry = _box.get(id);
    if (entry == null) return null;
    final path = _pathFrom(entry);
    if (path != null && Hive.isBoxOpen('AppPrefs')) {
      await markPendingFiles(
          Hive.box('AppPrefs'), podcastDownloadPendingKey(id), [path]);
    }
    await _box.delete(id);
    _downloadedIds.remove(id);
    return (id: id, entry: entry, path: path);
  }

  /// Undo for [takeOut].
  static Future<void> restore(PodcastDownloadRemoval removal) async {
    if (Hive.isBoxOpen('AppPrefs')) {
      await clearPendingFiles(
          Hive.box('AppPrefs'), podcastDownloadPendingKey(removal.id));
    }
    if (!Hive.isBoxOpen('PodcastDownloads') || _box.containsKey(removal.id)) {
      return;
    }
    await _box.put(removal.id, removal.entry);
    if (removal.path != null) _downloadedIds.add(removal.id);
  }

  /// Undo is no longer offered: the file goes, unless the episode was
  /// downloaded again meanwhile.
  static Future<void> commitRemoval(PodcastDownloadRemoval removal) async {
    final back =
        Hive.isBoxOpen('PodcastDownloads') && _box.containsKey(removal.id);
    final path = removal.path;
    if (!back && path != null) await deleteFiles([path]);
    if (Hive.isBoxOpen('AppPrefs')) {
      await clearPendingFiles(
          Hive.box('AppPrefs'), podcastDownloadPendingKey(removal.id));
    }
  }

  static Future<void> delete(String id) async {
    if (!Hive.isBoxOpen('PodcastDownloads')) return;
    final p = _pathFrom(_box.get(id));
    if (p != null) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await _box.delete(id);
    _downloadedIds.remove(id);
  }

  /// All downloaded episode ids with existing files (for the Downloads hub).
  static List<String> downloadedIds() {
    if (!Hive.isBoxOpen('PodcastDownloads')) return [];
    _warmCache();
    // Reconcile with Hive in case entries were written after the first warm.
    for (final key in _box.keys) {
      final id = key.toString();
      if (!_downloadedIds.contains(id) && _pathFrom(_box.get(key)) != null) {
        _downloadedIds.add(id);
      }
    }
    final out = <String>[];
    for (final id in _downloadedIds.toList()) {
      if (localPath(id) != null) out.add(id);
    }
    return out;
  }

  /// Playable MediaItems for the Downloads hub (legacy path-only rows included).
  static List<MediaItem> downloadedItems() {
    if (!Hive.isBoxOpen('PodcastDownloads')) return [];
    _warmCache();
    final out = <MediaItem>[];
    for (final id in downloadedIds()) {
      final item = toMediaItem(id);
      if (item != null) out.add(item);
    }
    return out;
  }

  static MediaItem? toMediaItem(String id) {
    final path = localPath(id);
    if (path == null) return null;
    final raw = _box.get(id);
    if (raw is Map) {
      final r = Map<String, dynamic>.from(raw);
      return MediaItem(
        id: id,
        title: (r['title'] ?? id).toString(),
        artist: r['artist']?.toString(),
        duration: r['durationMs'] is int
            ? Duration(milliseconds: r['durationMs'] as int)
            : null,
        artUri: r['artUri'] != null ? Uri.tryParse('${r['artUri']}') : null,
        extras: {
          'url': r['url'] ?? 'file://$path',
          'isPodcast': true,
          if (r['feedUrl'] != null) 'feedUrl': r['feedUrl'],
          if (r['description'] != null) 'description': r['description'],
          if (r['date'] != null) 'date': r['date'],
          if (r['pubDateMs'] != null) 'pubDateMs': r['pubDateMs'],
          if (r['chaptersUrl'] != null) 'chaptersUrl': r['chaptersUrl'],
          if (r['transcriptUrl'] != null) 'transcriptUrl': r['transcriptUrl'],
          if (r['transcriptType'] != null)
            'transcriptType': r['transcriptType'],
          'localPath': path,
        },
      );
    }
    // Legacy path-only entry.
    final name = path.split('/').last;
    return MediaItem(
      id: id,
      title: name,
      artist: null,
      extras: {
        'url': 'file://$path',
        'isPodcast': true,
        'localPath': path,
      },
    );
  }

  static String _ext(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot != -1 && path.length - dot <= 5) return path.substring(dot);
    return '.mp3';
  }
}
