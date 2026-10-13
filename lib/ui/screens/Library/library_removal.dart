/// Taking a song out of the library with Undo, like YouTube Music's
/// "Removed from library · Undo": its entries and its place in the list
/// go at once, its files only once Undo is no longer offered.
library;

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

/// Files of removed songs whose Undo is still on offer, by song id, in
/// AppPrefs: what a closed app left behind is deleted on the next start
/// ([purgePendingLibraryFiles]).
const pendingLibraryFilesKey = 'pendingLibraryFileDeletes';

/// What Undo needs to put a removed song back.
class LibrarySongRemoval {
  const LibrarySongRemoval({
    required this.song,
    required this.files,
    this.download,
    this.cached,
    this.listIndex = -1,
    this.searchIndex = -1,
  });

  final MediaItem song;

  /// Its `SongDownloads` and `SongsCache` entries (null: it had none).
  final Object? download;
  final Object? cached;

  /// Its downloaded / cached audio and thumbnail.
  final List<String> files;

  /// Where it sat in the Songs list, and in the full list behind a search
  /// (-1: not there).
  final int listIndex;
  final int searchIndex;
}

/// The files a library song keeps on the device: the download (its entry's
/// `url`), the listening cache (with its content-type side file) and the
/// thumbnail.
List<String> libraryFilesOf({
  required String id,
  required Object? download,
  required bool cached,
  required String cacheDir,
  required String supportDir,
}) {
  final url = download is Map ? download['url'] : null;
  return [
    if (url is String && url.isNotEmpty && !url.startsWith('http')) url,
    if (cached) ...[
      '$cacheDir/cachedSongs/$id.mp3',
      '$cacheDir/cachedSongs/$id.mp3.mime',
    ],
    '$supportDir/thumbnails/$id.png',
  ];
}

/// Inserts [item] at [index], or at the end when the list got shorter.
void insertClamped<T>(List<T> list, int index, T item) =>
    list.insert(index.clamp(0, list.length), item);

Map<String, dynamic> _pending(Box prefs) {
  final raw = prefs.get(pendingLibraryFilesKey);
  return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
}

Future<void> markPendingLibraryFiles(
    Box prefs, String id, List<String> files) async {
  final next = _pending(prefs)..[id] = files;
  await prefs.put(pendingLibraryFilesKey, next);
}

Future<void> clearPendingLibraryFiles(Box prefs, String id) async {
  final next = _pending(prefs);
  if (next.remove(id) == null) return;
  next.isEmpty
      ? await prefs.delete(pendingLibraryFilesKey)
      : await prefs.put(pendingLibraryFilesKey, next);
}

/// Deletes [files] that exist; one that can't be deleted is skipped.
Future<void> deleteLibraryFiles(Iterable<String> files) async {
  for (final path in files) {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Gone already, or not ours to delete: nothing to undo either way.
    }
  }
}

/// Start-up: deletes the files of removals an app closed before it could,
/// unless the song is back in the library ([inLibrary]).
Future<void> purgePendingLibraryFiles(Box prefs,
    {required bool Function(String id) inLibrary}) async {
  final pending = _pending(prefs);
  if (pending.isEmpty) return;
  for (final MapEntry(:key, :value) in pending.entries) {
    if (inLibrary(key) || value is! List) continue;
    await deleteLibraryFiles(value.map((f) => '$f'));
  }
  await prefs.delete(pendingLibraryFilesKey);
}
