import '../models/artist.dart';
import '../models/playlist.dart';
import 'continuations.dart';
import 'nav_parser.dart';

/// A page of a YouTube Music library list (Library › Playlists, its
/// artist subscriptions): the list's items and the token of the page
/// after it (null on the last).
typedef LibraryPage = ({List<dynamic> items, String? next});

/// The first page of a library's list, as ytmusicapi's
/// get_library_contents finds it: a grid (playlists) or a shelf (artists),
/// in an itemSectionRenderer of the section list or straight in it. Empty
/// when the library is.
LibraryPage libraryFirstPage(Map<String, dynamic> response) {
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
      final inner =
          nav(section, ['itemSectionRenderer', 'contents', 0]) ?? section;
      final list =
          nav(inner, ['gridRenderer']) ?? nav(inner, ['musicShelfRenderer']);
      if (list is Map) return _page(list);
    }
  }
  return (items: const [], next: null);
}

/// A page after the first, in any form YouTube hands out: a grid's or a
/// shelf's continuation, or items appended by a continuation command.
LibraryPage libraryNextPage(Map<String, dynamic> response) {
  final list = nav(response, ['continuationContents', 'gridContinuation']) ??
      nav(response, ['continuationContents', 'musicShelfContinuation']);
  if (list is Map) return _page(list);
  final items = nav(response, CONTINUATION_ITEMS);
  if (items is List) return (items: items, next: getContinuationToken(items));
  return (items: const [], next: null);
}

LibraryPage _page(Map list) {
  final items = list['items'] ?? list['contents'];
  final page = items is List ? items : const [];
  final String? next =
      nav(list, ['continuations', 0, 'nextContinuationData', 'continuation']) ??
          getContinuationToken(page);
  return (items: page, next: next);
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

/// The artists among a library shelf's [items] (ytmusicapi's
/// parse_artists): the rows that open an artist's channel (UC…), with
/// their name, subscribers and picture.
List<Artist> parseLibraryArtists(List<dynamic> items) {
  final artists = <Artist>[];
  for (final item in items) {
    final data = nav(item, ['musicResponsiveListItemRenderer']);
    final id = nav(data, navigation_browse_id);
    if (data is! Map<String, dynamic> ||
        id is! String ||
        !id.startsWith('UC')) {
      continue;
    }
    final name = nav(getFlexColumnItem(data, 0), ['text', 'runs', 0, 'text']);
    if (name is! String || name.isEmpty) continue;
    artists.add(Artist.fromJson({
      'artist': name,
      'browseId': id,
      'subscribers':
          nav(getFlexColumnItem(data, 1), ['text', 'runs', 0, 'text']),
      'thumbnails': nav(data,
          ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']),
    }));
  }
  return artists;
}
