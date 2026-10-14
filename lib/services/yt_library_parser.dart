import '../models/playlist.dart';
import 'continuations.dart';
import 'nav_parser.dart';

/// A page of a YouTube Music library grid (its Library › Playlists): the
/// grid's items and the token of the page after it (null on the last).
typedef LibraryGridPage = ({List<dynamic> items, String? next});

/// The first page of a library's grid, as ytmusicapi's
/// get_library_contents finds it: in an itemSectionRenderer of the
/// section list, or straight in it. Empty when the library is.
LibraryGridPage libraryGridFirstPage(Map<String, dynamic> response) {
  final sections = nav(response, [
    'contents',
    'singleColumnBrowseResultsRenderer',
    'tabs',
    0,
    'tabRenderer',
    'content',
    'sectionListRenderer',
    'contents'
  ]);
  if (sections is List) {
    for (final section in sections) {
      final grid = nav(section,
              ['itemSectionRenderer', 'contents', 0, 'gridRenderer']) ??
          nav(section, ['gridRenderer']);
      if (grid is Map) return _gridPage(grid);
    }
  }
  return (items: const [], next: null);
}

/// A page after the first, in either form YouTube hands out: a
/// gridContinuation, or items appended by a continuation command.
LibraryGridPage libraryGridNextPage(Map<String, dynamic> response) {
  final grid = nav(response, ['continuationContents', 'gridContinuation']);
  if (grid is Map) return _gridPage(grid);
  final items = nav(response, CONTINUATION_ITEMS);
  if (items is List) return (items: items, next: getContinuationToken(items));
  return (items: const [], next: null);
}

LibraryGridPage _gridPage(Map grid) {
  final items = grid['items'] is List ? grid['items'] as List : const [];
  final String? next =
      nav(grid, ['continuations', 0, 'nextContinuationData', 'continuation']) ??
          getContinuationToken(items);
  return (items: items, next: next);
}

/// The playlists among a library grid's [items]: the cards that open a
/// playlist (VL…), not the New playlist card nor a continuation.
List<Playlist> parseLibraryPlaylists(List<dynamic> items) {
  final playlists = <Playlist>[];
  for (final item in items) {
    final data = nav(item, ['musicTwoRowItemRenderer']);
    final id = nav(data, ['title', 'runs', 0, ...navigation_browse_id]);
    if (data is! Map<String, dynamic> ||
        id is! String ||
        !id.startsWith('VL')) {
      continue;
    }
    try {
      playlists.add(parsePlaylist(data));
    } catch (_) {
      // A card of another shape: left out.
    }
  }
  return playlists;
}
