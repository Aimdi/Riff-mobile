import 'dart:async';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'music_service.dart';

/// Resolves a square cover for a track whose only art is a 16:9 YouTube video
/// frame. YouTube hosts the real square cover on the song's audio-track (ATV)
/// version; we find it by a song-filtered search and cache the result (in
/// memory + Hive) so each videoId is looked up at most once. Lookups are
/// dedup'd and throttled so a fast scroll can't fire a request storm.
class CoverResolver {
  CoverResolver._();

  static const boxName = 'SquareCovers';
  static const _maxConcurrent = 3;

  // videoId -> square url; '' means "resolved, none found" (don't retry).
  static final Map<String, String> _mem = {};
  static final Set<String> _inflight = {};
  static final List<_Job> _queue = [];
  static int _active = 0;

  static Box? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  /// Synchronous cache read: a square URL, '' for known-none, or null if the
  /// videoId hasn't been resolved yet.
  static String? cached(String videoId) {
    final m = _mem[videoId];
    if (m != null) return m;
    final b = _box?.get(videoId);
    if (b is String) {
      _mem[videoId] = b;
      return b;
    }
    return null;
  }

  /// Kicks off (or joins) a resolution. Completes with the square URL, or null
  /// if none was found / already resolving.
  static Future<String?> resolve(String videoId,
      {String? title, String? artist}) {
    final c = cached(videoId);
    if (c != null) return Future.value(c.isEmpty ? null : c);
    if (_inflight.contains(videoId)) return Future.value(null);
    _inflight.add(videoId);
    final completer = Completer<String?>();
    _queue.add(_Job(videoId, title, artist, completer));
    _pump();
    return completer.future;
  }

  static void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active++;
      _run(job).whenComplete(() {
        _active--;
        _inflight.remove(job.videoId);
        _pump();
      });
    }
  }

  static Future<void> _run(_Job job) async {
    try {
      final url = await Get.find<MusicServices>()
          .squareCoverForVideo(job.videoId, title: job.title, artist: job.artist);
      final val = url ?? '';
      _mem[job.videoId] = val;
      _box?.put(job.videoId, val);
      job.completer.complete(val.isEmpty ? null : val);
    } catch (_) {
      // Leave uncached so a later attempt can retry (transient failure).
      job.completer.complete(null);
    }
  }
}

class _Job {
  _Job(this.videoId, this.title, this.artist, this.completer);
  final String videoId;
  final String? title;
  final String? artist;
  final Completer<String?> completer;
}
