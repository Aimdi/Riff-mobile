import '/ui/player/long_form_queue.dart';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '/services/offline_playback.dart';
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
    _sweepParts(dir);
    return dir.path;
  }

  /// A download broken off keeps what it got in `<file>.part`, and what the
  /// server said of the file in `<file>.part.json` (its address, and its
  /// ETag or Last-Modified), so the next try asks for the rest only (Range,
  /// If-Range), as AntennaPod resumes its downloads: the rest when the
  /// server says it's the same file, else all of it again.
  static const _partSuffix = '.part';
  static const _metaSuffix = '.part.json';

  /// Partial downloads untouched this long are deleted.
  static const partsKeptFor = Duration(days: 7);

  /// A download broken off with a connection there is tried again after
  /// this, then twice this, before it's given up (what it got is kept for
  /// the next try).
  @visibleForTesting
  static Duration retryDelay = const Duration(seconds: 2);
  static const _tries = 3;

  static void _sweepParts(Directory dir) {
    final before = DateTime.now().subtract(partsKeptFor);
    try {
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith(_partSuffix) &&
            !file.path.endsWith(_metaSuffix)) {
          continue;
        }
        if (file.lastModifiedSync().isBefore(before)) file.deleteSync();
      }
    } catch (_) {}
  }

  static int _partLength(String path) {
    final part = File('$path$_partSuffix');
    return part.existsSync() ? part.lengthSync() : 0;
  }

  static void _dropPart(String path) {
    for (final suffix in [_partSuffix, _metaSuffix]) {
      try {
        final file = File('$path$suffix');
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  /// What the server said of the file at [url] when [path]'s download broke
  /// off (the If-Range to resume it with), or null when it can't resume.
  static String? _validatorKept(String path, String url) {
    try {
      final meta = File('$path$_metaSuffix');
      if (_partLength(path) == 0 || !meta.existsSync()) return null;
      final kept = jsonDecode(meta.readAsStringSync());
      if (kept is! Map || kept['url'] != url) return null;
      final validator = kept['validator'];
      return validator is String && validator.isNotEmpty ? validator : null;
    } catch (_) {
      return null;
    }
  }

  /// What resumes the file later: its ETag (a weak one can't), else its
  /// Last-Modified.
  static String? _validatorOf(Headers headers) {
    final etag = headers.value('etag');
    if (etag != null && !etag.startsWith('W/')) return etag;
    return headers.value('last-modified');
  }

  /// Where a partial answer (Content-Range) starts.
  static int? _rangeStart(String? contentRange) {
    final start =
        RegExp(r'^bytes\s+(\d+)-').firstMatch(contentRange?.trim() ?? '');
    return start == null ? null : int.tryParse(start.group(1)!);
  }

  /// Fetches [url] into [path], after what a try before got when the server
  /// says it's the same file.
  static Future<void> _fetch(
      String url, String path, void Function(double)? onProgress) async {
    final part = File('$path$_partSuffix');
    final meta = File('$path$_metaSuffix');
    final discard = File('$path.discard');
    final validator = _validatorKept(path, url);
    if (validator == null) _dropPart(path);
    var offset = validator == null ? 0 : part.lengthSync();
    final cancel = CancelToken();
    try {
      await _dio.download(
        url,
        (Headers headers) {
          final range = headers.value('content-range');
          final got = _validatorOf(headers);
          if (offset > 0 &&
              !(_rangeStart(range) == offset &&
                  (got == null || got == validator))) {
            // A part of another file can't follow on: called off, for all
            // of it again.
            if (range != null) {
              cancel.cancel(const _PartOfAnother());
              return discard.path;
            }
            // The whole file (the server not resuming, or it changed).
            offset = 0;
            part.writeAsBytesSync(const [], flush: true);
          }
          meta.writeAsStringSync(jsonEncode({'url': url, 'validator': got}),
              flush: true);
          return part.path;
        },
        cancelToken: cancel,
        deleteOnError: false,
        fileAccessMode: FileAccessMode.append,
        options: Options(headers: {
          if (offset > 0) 'range': 'bytes=$offset-',
          if (offset > 0) 'if-range': validator,
        }),
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress((offset + received) / (offset + total));
          }
        },
      );
    } finally {
      if (discard.existsSync()) discard.deleteSync();
    }
    // An older copy (one kept for Undo) gives way, as it did before.
    final done = File(path);
    if (done.existsSync()) done.deleteSync();
    await part.rename(path);
    if (meta.existsSync()) meta.deleteSync();
  }

  /// Whether a download that failed with [e] is worth trying again: the
  /// connection broke it off (or the file changed under it, so it starts
  /// over), not the server refusing it.
  static bool _worthAnotherTry(Object e, String path) {
    if (e is! DioException) return false;
    if (e.error is _PartOfAnother) {
      _dropPart(path);
      return true;
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        // More asked for than there is: the file changed; from the start.
        if (e.response?.statusCode == 416) {
          _dropPart(path);
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  /// Fetches [episode]'s [url] into [path], resuming what it got when it's
  /// broken off: with the connection gone, once it's back (nothing got yet,
  /// it fails as before); with it there, after [retryDelay], twice. False
  /// when given up.
  static Future<bool> _fetchResuming(MediaItem episode, String url, String path,
      void Function(double)? onProgress) async {
    var brokenOff = 0;
    while (true) {
      try {
        await _fetch(url, path, onProgress);
        return true;
      } catch (e) {
        if (!_worthAnotherTry(e, path)) return false;
        if (OfflinePlayback.noConnection.isTrue) {
          if (_partLength(path) == 0) return false;
          await _connectionBack(episode);
          continue;
        }
        if (++brokenOff >= _tries) return false;
        await Future<void>.delayed(retryDelay * brokenOff);
      }
    }
  }

  /// Until there's a connection again, the notification saying so.
  static Future<void> _connectionBack(MediaItem episode) async {
    if (OfflinePlayback.noConnection.isFalse) return;
    _noticeText = 'waitingForConnection'.tr;
    _noticeShow();
    await OfflinePlayback.noConnection.stream.firstWhere((none) => !none);
    _noticeText = episode.title;
    _noticeShow();
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
      if (!await _fetchResuming(episode, url, path, onProgress)) return false;
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

/// A partial answer to a resumed download that isn't of the file it began.
class _PartOfAnother implements Exception {
  const _PartOfAnother();
}
