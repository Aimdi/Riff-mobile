import 'nav_parser.dart';
import 'search_top_result.dart';

/// What YouTube Music suggests as you type (music/get_search_suggestions),
/// as its search box shows it: searches to complete what you typed, then
/// the songs, artists, albums, playlists and podcasts they'd find, to play
/// or open straight away (Spotify, Apple Music, Metrolist and InnerTune
/// show them too).
class SearchSuggestions {
  const SearchSuggestions({this.queries = const [], this.items = const []});

  /// Searches, in the order given.
  final List<String> queries;

  /// Results, as the search's overview keeps their kinds: MediaItems (songs,
  /// videos), Artists, Albums and Playlists (podcasts too).
  final List<Object> items;

  /// What YouTube Music's answer holds: its sections' searches (rows with no
  /// search, as history ones, are left out) and its results.
  static SearchSuggestions fromResponse(Object? json) {
    final queries = <String>[];
    final items = <Object>[];
    final sections = nav(json, ['contents']);
    for (final section in sections is List ? sections : const []) {
      final rows =
          nav(section, ['searchSuggestionsSectionRenderer', 'contents']);
      for (final row in rows is List ? rows : const []) {
        final query = nav(row, [
          'searchSuggestionRenderer',
          'navigationEndpoint',
          'searchEndpoint',
          'query'
        ]);
        if (query is String) {
          queries.add(query);
          continue;
        }
        final result =
            row is Map ? row['musicResponsiveListItemRenderer'] : null;
        final item = result is Map ? suggested(result) : null;
        if (item != null) items.add(item);
      }
    }
    return SearchSuggestions(queries: queries, items: items);
  }

  /// One suggested result (a musicResponsiveListItemRenderer); null for
  /// anything the search's overview doesn't show (a profile, an episode).
  static Object? suggested(Map row) {
    try {
      final endpoint = row['navigationEndpoint'];
      final videoId = nav(endpoint, ['watchEndpoint', 'videoId']) ??
          nav(row, ['playlistItemData', 'videoId']) ??
          nav(row, [
            ...play_button,
            'playNavigationEndpoint',
            'watchEndpoint',
            'videoId'
          ]);
      final videoType = nav(endpoint, navigation_video_type) ??
          nav(row, [
            ...play_button,
            'playNavigationEndpoint',
            ...navigation_video_type
          ]);
      final kind = searchKindOf(
          pageType: nav(endpoint, ['browseEndpoint', ...page_type]),
          videoType: videoType,
          watch: videoId != null);
      if (kind == null) return null;
      List? column(int i) => nav(row, [
            'flexColumns',
            i,
            'musicResponsiveListItemFlexColumnRenderer',
            'text',
            'runs'
          ]) as List?;
      final titleRuns = column(0) ?? const [];
      return searchResultItem(
        kind: kind,
        title:
            titleRuns.isEmpty ? '' : '${titleRuns.first['text'] ?? ''}'.trim(),
        runs: column(1) ?? const [],
        thumbs: nav(row, thumbnails),
        browseId: nav(endpoint, ['browseEndpoint', 'browseId'])?.toString(),
        videoId: videoId?.toString(),
        videoType: videoType?.toString(),
        explicit: hasExplicitBadge(row),
        audioPlaylistId: nav(row, audio_watch_playlist_id)?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}
