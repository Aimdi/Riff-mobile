import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads podcast episodes (direct enclosure URLs) to local storage so they
/// can be played offline. Records live in the `PodcastDownloads` Hive box,
/// keyed by episode id. Values are either a legacy absolute path [String] or a
/// metadata [Map] with at least `path`. Playback prefers the local copy via
/// MyAudioHandler.checkNGetUrl.
class PodcastDownloadService {
  PodcastDownloadService._();

  static final _dio = Dio();
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

  /// Download [episode]'s audio. Returns true on success (or if already
  /// downloaded). [onProgress] receives 0..1.
  static Future<bool> download(MediaItem episode,
      {void Function(double)? onProgress}) async {
    final url = episode.extras?['url'] as String?;
    if (url == null || url.isEmpty) return false;
    if (isDownloaded(episode.id) && localPath(episode.id) != null) return true;
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
        'description': episode.extras?['description'],
        'date': episode.extras?['date'],
        'pubDateMs': episode.extras?['pubDateMs'],
        'chaptersUrl': episode.extras?['chaptersUrl'],
        'transcriptUrl': episode.extras?['transcriptUrl'],
        'transcriptType': episode.extras?['transcriptType'],
      });
      _downloadedIds.add(episode.id);
      return true;
    } catch (_) {
      return false;
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
