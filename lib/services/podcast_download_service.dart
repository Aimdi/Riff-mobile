import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads podcast episodes (direct enclosure URLs) to local storage so they
/// can be played offline. Records live in the `PodcastDownloads` Hive box,
/// keyed by the episode id -> absolute file path. Playback prefers the local
/// copy via MyAudioHandler.checkNGetUrl.
class PodcastDownloadService {
  PodcastDownloadService._();

  static final _dio = Dio();
  static final Set<String> _downloadedIds = {};
  static bool _cacheWarmed = false;

  static Box get _box => Hive.box('PodcastDownloads');

  static void _warmCache() {
    if (_cacheWarmed || !Hive.isBoxOpen('PodcastDownloads')) return;
    _cacheWarmed = true;
    for (final key in _box.keys) {
      final p = _box.get(key);
      if (p is String && p.isNotEmpty) {
        _downloadedIds.add(key.toString());
      }
    }
  }

  /// Fast path for UI (long-press sheet) — memory only, no disk I/O.
  static bool isDownloaded(String id) {
    _warmCache();
    return _downloadedIds.contains(id);
  }

  /// Absolute local path if the episode is downloaded and the file still
  /// exists, else null. May touch the filesystem (playback / cleanup).
  static String? localPath(String id) {
    if (!Hive.isBoxOpen('PodcastDownloads')) return null;
    _warmCache();
    if (!_downloadedIds.contains(id)) return null;
    final p = _box.get(id);
    if (p is String && p.isNotEmpty && File(p).existsSync()) return p;
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
      await _box.put(episode.id, path);
      _downloadedIds.add(episode.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String id) async {
    if (!Hive.isBoxOpen('PodcastDownloads')) return;
    final p = _box.get(id);
    if (p is String && p.isNotEmpty) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await _box.delete(id);
    _downloadedIds.remove(id);
  }

  static String _ext(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot != -1 && path.length - dot <= 5) return path.substring(dot);
    return '.mp3';
  }
}
