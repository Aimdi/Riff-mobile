/// Taking a song out of the library with Undo, like YouTube Music's
/// "Removed from library · Undo": its entries and its place in the list
/// go at once, its files only once Undo is no longer offered.
library;

import 'package:audio_service/audio_service.dart';

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
