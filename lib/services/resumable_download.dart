/// Files downloaded so that one cut off picks up where it broke off, as
/// AntennaPod resumes its downloads: podcast episodes
/// (PodcastDownloadService) and audiobooks (AudiobookDownloads).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';

import '/services/offline_playback.dart';

class ResumableDownload {
  ResumableDownload._();

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

  /// Partial downloads in [dir] untouched for [partsKeptFor], deleted.
  static void sweepParts(Directory dir) {
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
  static Future<void> _fetch(Dio dio, String url, String path,
      void Function(double)? onProgress, CancelToken? calledOff) async {
    final part = File('$path$_partSuffix');
    final meta = File('$path$_metaSuffix');
    final discard = File('$path.discard');
    final validator = _validatorKept(path, url);
    if (validator == null) _dropPart(path);
    var offset = validator == null ? 0 : part.lengthSync();
    final cancel = CancelToken();
    // Called off where it was asked for (Cancel): this try with it.
    calledOff?.whenCancel.then((e) => cancel.cancel(e.error)).ignore();
    try {
      await dio.download(
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

  /// Fetches [url] into [path] with [dio], resuming what it got when it's
  /// broken off: with the connection gone, once it's back
  /// ([waitForConnection], which waits for it; nothing got yet, it fails at
  /// once); with it there, after [retryDelay], twice. False when given up,
  /// or called off with [cancelToken] (what it got is kept).
  static Future<bool> fetch(Dio dio, String url, String path,
      {void Function(double)? onProgress,
      required Future<void> Function() waitForConnection,
      CancelToken? cancelToken}) async {
    var brokenOff = 0;
    while (true) {
      if (cancelToken?.isCancelled ?? false) return false;
      try {
        await _fetch(dio, url, path, onProgress, cancelToken);
        return true;
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) return false;
        if (!_worthAnotherTry(e, path)) return false;
        if (OfflinePlayback.noConnection.isTrue) {
          if (_partLength(path) == 0) return false;
          await waitForConnection();
          continue;
        }
        if (++brokenOff >= _tries) return false;
        await Future<void>.delayed(retryDelay * brokenOff);
      }
    }
  }
}

/// A partial answer to a resumed download that isn't of the file it began.
class _PartOfAnother implements Exception {
  const _PartOfAnother();
}
