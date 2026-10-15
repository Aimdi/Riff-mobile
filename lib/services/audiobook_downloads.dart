/// Audiobooks kept on the phone to listen offline, as Audible and the
/// Audiobookshelf app keep them: each chapter's file under
/// audiobook_downloads/<book>/, and the book's chapters in the
/// AudiobookDownloads box (by book id), so a book downloaded plays with no
/// server and no connection. Books download one after another, a chapter at
/// a time, picking up where one broke off (ResumableDownload), on Wi-Fi only
/// when Download on Wi-Fi only is on; a chapter already there isn't fetched
/// again, so a book whose download stopped goes on from where it stopped.
library;

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '/services/download_notice.dart';
import '/services/offline_playback.dart';
import '/services/resumable_download.dart';
import '/services/wifi_only_downloads.dart';

/// How a book's download ended.
enum BookDownload { done, failed, cancelled }

/// A book on the phone, as the Saved tab shows it.
class DownloadedBook {
  const DownloadedBook({
    required this.id,
    required this.title,
    required this.author,
    required this.art,
    required this.free,
  });

  final String id;
  final String title;
  final String author;

  /// Its cover's address ('' for none).
  final String art;

  /// A LibriVox book (else one from your Audiobookshelf server).
  final bool free;
}

class AudiobookDownloads {
  AudiobookDownloads._();

  static const boxName = 'AudiobookDownloads';

  /// Books downloading or waiting their turn, by id: how far along (0–1).
  static final progress = <String, double>{}.obs;

  /// Bumps when a book is downloaded or removed.
  static final rev = 0.obs;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Where the books go (the app's own storage).
  @visibleForTesting
  static Future<Directory> Function() baseDir = getApplicationSupportDirectory;

  static Box? get _box => Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  static bool isDownloaded(String bookId) => _box?.containsKey(bookId) ?? false;

  static bool isDownloading(String bookId) => progress.containsKey(bookId);

  /// Chapter id → its file, for the books downloaded in [_indexed].
  static Map<String, String> _files = const {};
  static Box? _indexed;

  static Map<String, String> get _index {
    final box = _box;
    if (box == null) return const {};
    if (!identical(box, _indexed)) {
      _indexed = box;
      _files = {
        for (final book in box.values)
          if (book is Map && book['chapters'] is List)
            for (final c in book['chapters'] as List)
              if (c is Map && c['id'] is String && c['path'] is String)
                c['id'] as String: c['path'] as String,
      };
    }
    return _files;
  }

  static void _reindex() => _indexed = null;

  /// The file of the chapter [chapterId], when its book is downloaded.
  static String? localPath(String chapterId) {
    final path = _index[chapterId];
    return path != null && File(path).existsSync() ? path : null;
  }

  /// Where the chapter [chapterId] plays from: its file when its book is
  /// downloaded (its address [url] kept in [extras] as remoteUrl), else
  /// [url], its address again once the download is gone.
  static String? playUrl(
      String chapterId, String? url, Map<String, dynamic>? extras) {
    final local = localPath(chapterId);
    if (local != null) {
      if (url != null && url.isNotEmpty && !url.startsWith('file://')) {
        extras?['remoteUrl'] = url;
      }
      return 'file://$local';
    }
    final remote = extras?['remoteUrl'];
    if ((url?.startsWith('file://') ?? false) &&
        remote is String &&
        remote.isNotEmpty) {
      return remote;
    }
    return url;
  }

  /// The downloaded book's chapters, as they were when it was downloaded:
  /// what plays it with no server or connection.
  static List<MediaItem>? chapters(String bookId) {
    final book = _box?.get(bookId);
    if (book is! Map || book['chapters'] is! List) return null;
    final out = [
      for (final c in book['chapters'] as List)
        if (_chapterFromJson(c) case final chapter?) chapter
    ];
    return out.isEmpty ? null : out;
  }

  /// The books downloaded, the latest first.
  static List<DownloadedBook> books() {
    final box = _box;
    if (box == null) return const [];
    final found = <(int, DownloadedBook)>[];
    for (final key in box.keys) {
      final book = box.get(key);
      if (book is! Map || book['chapters'] is! List) continue;
      final list = book['chapters'] as List;
      final first = list.isEmpty ? null : _chapterFromJson(list.first);
      if (first == null) continue;
      final at = book['at'];
      found.add((
        at is int ? at : 0,
        DownloadedBook(
          id: '$key',
          title: first.album ?? first.title,
          author: first.artist ?? '',
          art: first.artUri?.toString() ?? '',
          free: first.id.startsWith('lv_'),
        ),
      ));
    }
    found.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, book) in found) book];
  }

  /// Each book downloading or waiting its turn: calls it off (Cancel).
  static final _calledOff = <String, CancelToken>{};

  /// The books' downloads, one after another.
  static Future<void> _line = Future.value();

  /// Downloads the book [bookId], its [chapters] in order (fresh from where
  /// it plays from: an Audiobookshelf address carries a token that ages),
  /// once the books before it are done. Chapters downloaded are kept when
  /// one can't be had, for the next try.
  static Future<BookDownload> download(
      String bookId, List<MediaItem> chapters) {
    if (isDownloaded(bookId)) return Future.value(BookDownload.done);
    if (chapters.isEmpty || isDownloading(bookId)) {
      return Future.value(BookDownload.failed);
    }
    final calledOff = _calledOff[bookId] = CancelToken();
    progress[bookId] = 0;
    final run = _line.then((_) => _download(bookId, chapters, calledOff));
    _line = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  static Future<BookDownload> _download(
      String bookId, List<MediaItem> chapters, CancelToken calledOff) async {
    bool wanted() => !calledOff.isCancelled;
    final title = chapters.first.album ?? chapters.first.title;
    void notice(int done, String text) =>
        DownloadNotice.update(DownloadNotice.books,
            done: done, total: chapters.length, text: text);
    try {
      if (!wanted()) return BookDownload.cancelled;
      final dir = await _bookDir(bookId);
      final kept = <Map<String, dynamic>>[];
      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        final url = chapter.extras?['url'];
        if (url is! String || url.isEmpty) return BookDownload.failed;
        final path = '${dir.path}/${_safe(chapter.id)}${_extension(url)}';
        if (!File(path).existsSync()) {
          // Download on Wi-Fi only: on mobile data, it waits for Wi-Fi.
          if (!await WifiOnlyDownloads.waitForWifi(
                  wanted: wanted,
                  onWait: () => notice(i, 'waitingForWifi'.tr)) ||
              !wanted()) {
            return BookDownload.cancelled;
          }
          notice(i, title);
          final fetched = await ResumableDownload.fetch(_dio, url, path,
              onProgress: (part) =>
                  progress[bookId] = (i + part) / chapters.length,
              waitForConnection: () async {
                notice(i, 'waitingForConnection'.tr);
                await _connectionBack(calledOff);
                notice(i, title);
              },
              cancelToken: calledOff);
          if (!wanted()) return BookDownload.cancelled;
          if (!fetched) return BookDownload.failed;
        }
        kept.add({..._chapterToJson(chapter), 'path': path});
        progress[bookId] = (i + 1) / chapters.length;
      }
      // The cover too, so the book shows as it is with no connection.
      final cover = await _keepCover(dir, chapters.first.artUri);
      if (cover != null) {
        for (final chapter in kept) {
          chapter['artUri'] = Uri.file(cover).toString();
        }
      }
      _dropOthers(dir, {
        for (final c in kept) c['path'] as String,
        if (cover != null) cover,
      });
      await _box?.put(bookId, {
        'chapters': kept,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
      // Removed meanwhile.
      if (!wanted()) await _box?.delete(bookId);
      _reindex();
      rev.value++;
      return wanted() ? BookDownload.done : BookDownload.cancelled;
    } catch (_) {
      return wanted() ? BookDownload.failed : BookDownload.cancelled;
    } finally {
      if (identical(_calledOff[bookId], calledOff)) _calledOff.remove(bookId);
      progress.remove(bookId);
      if (progress.isEmpty) DownloadNotice.end(DownloadNotice.books);
      if (!wanted()) await _deleteFiles(bookId);
    }
  }

  /// Stops the book downloading, or waiting its turn, its files gone.
  static void cancel(String bookId) => _calledOff[bookId]?.cancel();

  /// The downloaded book gone from the phone (it plays from where it
  /// streams again).
  static Future<void> remove(String bookId) async {
    cancel(bookId);
    await _box?.delete(bookId);
    _reindex();
    rev.value++;
    await _deleteFiles(bookId);
  }

  /// Waits for the connection to come back, or the download to be called
  /// off.
  static Future<void> _connectionBack(CancelToken calledOff) async {
    if (OfflinePlayback.noConnection.isFalse) return;
    await Future.any([
      OfflinePlayback.noConnection.stream.firstWhere((none) => !none),
      calledOff.whenCancel,
    ]);
  }

  static Future<Directory> _bookDir(String bookId) async {
    final dir = Directory('${await _root()}/${_safe(bookId)}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _sweepStopped(dir.parent);
    ResumableDownload.sweepParts(dir);
    return dir;
  }

  /// The chapters of books whose download stopped and wasn't tried again
  /// for [ResumableDownload.partsKeptFor], deleted.
  static void _sweepStopped(Directory root) {
    final kept = {
      for (final id in [...?_box?.keys, ...progress.keys]) _safe('$id'),
    };
    final before = DateTime.now().subtract(ResumableDownload.partsKeptFor);
    try {
      for (final dir in root.listSync().whereType<Directory>()) {
        if (kept
            .contains(dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty))) {
          continue;
        }
        final files = dir.listSync().whereType<File>();
        if (files.every((f) => f.lastModifiedSync().isBefore(before))) {
          dir.deleteSync(recursive: true);
        }
      }
    } catch (_) {}
  }

  static Future<String> _root() async =>
      '${(await baseDir()).path}/audiobook_downloads';

  /// The book's cover from [art], kept in [dir] (one kept already stays);
  /// null when it can't be had.
  static Future<String?> _keepCover(Directory dir, Uri? art) async {
    if (art == null || !(art.isScheme('http') || art.isScheme('https'))) {
      return null;
    }
    final path = '${dir.path}/cover';
    if (File(path).existsSync()) return path;
    try {
      await _dio.downloadUri(art, '$path.part');
      await File('$path.part').rename(path);
      return path;
    } catch (_) {
      return null;
    }
  }

  /// The downloaded book's cover on the phone (a file:// address), or null.
  static String? coverOf(String bookId) {
    final book = _box?.get(bookId);
    final list = book is Map ? book['chapters'] : null;
    final first = list is List && list.isNotEmpty ? list.first : null;
    final art = first is Map ? '${first['artUri'] ?? ''}' : '';
    if (!art.startsWith('file://')) return null;
    return File(Uri.parse(art).toFilePath()).existsSync() ? art : null;
  }

  /// Files in [dir] that aren't the book's chapters now (of an earlier
  /// download of it), deleted.
  static void _dropOthers(Directory dir, Set<String> chapters) {
    try {
      for (final file in dir.listSync().whereType<File>()) {
        if (!chapters.contains(file.path)) file.deleteSync();
      }
    } catch (_) {}
  }

  static Future<void> _deleteFiles(String bookId) async {
    try {
      final dir = Directory('${await _root()}/${_safe(bookId)}');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  /// The file type of [url]'s file (.mp3 when it doesn't say).
  static String _extension(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 5) return name.substring(dot);
    return '.mp3';
  }

  /// A chapter as kept: its extras that can be (plain values, and lists and
  /// maps of them), so its book's bookkeeping (absItemId, audiobookId …)
  /// stays with it; not the server's listening session of then.
  static Map<String, dynamic> _chapterToJson(MediaItem chapter) => {
        'id': chapter.id,
        'title': chapter.title,
        if (chapter.album != null) 'album': chapter.album,
        if (chapter.artist != null) 'artist': chapter.artist,
        if (chapter.duration != null)
          'durationMs': chapter.duration!.inMilliseconds,
        if (chapter.artUri != null) 'artUri': chapter.artUri.toString(),
        'extras': {
          for (final e in (chapter.extras ?? const {}).entries)
            if (e.key != 'absSessionId' &&
                (e.value is String ||
                    e.value is num ||
                    e.value is bool ||
                    e.value is List ||
                    e.value is Map))
              e.key: e.value,
        },
      };

  static MediaItem? _chapterFromJson(dynamic json) {
    if (json is! Map || json['id'] is! String) return null;
    final duration = json['durationMs'];
    final art = json['artUri'];
    final extras = json['extras'];
    return MediaItem(
      id: json['id'] as String,
      title: '${json['title'] ?? ''}',
      album: json['album']?.toString(),
      artist: json['artist']?.toString(),
      duration: duration is int ? Duration(milliseconds: duration) : null,
      artUri: art is String ? Uri.tryParse(art) : null,
      extras: <String, dynamic>{
        if (extras is Map)
          for (final e in extras.entries) '${e.key}': e.value,
      },
    );
  }
}
