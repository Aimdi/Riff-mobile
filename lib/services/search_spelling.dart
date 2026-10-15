/// YouTube Music's spelling help for a search, as its own search page shows
/// it (Spotify's and Apple Music's do the same): results for the words it
/// took yours for, with a way back to the words as typed ("Showing results
/// for … · Search instead for …"), or only a suggestion ("Did you mean …").
class SearchSpelling {
  const SearchSpelling({
    required this.corrected,
    required this.applied,
    this.original,
    this.originalParams,
  });

  /// Where MusicServices.search keeps it among the results.
  static const key = 'spelling';

  /// The words YouTube Music took the search for, or suggests.
  final String corrected;

  /// The results are for [corrected] already; else it's only suggested.
  final bool applied;

  /// The words as typed, when the results are for [corrected].
  final String? original;

  /// The search parameters YouTube Music gives for searching [original]
  /// exactly (its spelling left alone).
  final String? originalParams;

  /// What a search's sections (its sectionListRenderer's contents) say:
  /// a showingResultsForRenderer or didYouMeanRenderer in an
  /// itemSectionRenderer, as NewPipe reads them. Null when neither is there.
  static SearchSpelling? fromSections(Object? sections) {
    if (sections is! List) return null;
    for (final section in sections) {
      final items = _at(section, const ['itemSectionRenderer', 'contents']);
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        if (item['showingResultsForRenderer'] case final Map showing) {
          final corrected = _query(showing, 'correctedQueryEndpoint') ??
              _text(showing['correctedQuery']);
          final original = _query(showing, 'originalQueryEndpoint') ??
              _text(showing['originalQuery']);
          if (corrected == null || _same(corrected, original)) continue;
          return SearchSpelling(
            corrected: corrected,
            applied: true,
            original: original,
            originalParams: _params(showing, 'originalQueryEndpoint'),
          );
        }
        if (item['didYouMeanRenderer'] case final Map didYouMean) {
          final corrected = _query(didYouMean, 'correctedQueryEndpoint') ??
              _text(didYouMean['correctedQuery']);
          if (corrected == null) continue;
          return SearchSpelling(corrected: corrected, applied: false);
        }
      }
    }
    return null;
  }

  static bool _same(String a, String? b) =>
      b != null && a.trim().toLowerCase() == b.trim().toLowerCase();

  static Object? _at(Object? json, List<String> path) {
    var at = json;
    for (final step in path) {
      if (at is! Map) return null;
      at = at[step];
    }
    return at;
  }

  static String? _nonEmpty(Object? text) {
    final s = text is String ? text.trim() : '';
    return s.isEmpty ? null : s;
  }

  /// A text's runs, joined.
  static String? _text(Object? text) {
    final runs = _at(text, const ['runs']);
    if (runs is! List) return _nonEmpty(_at(text, const ['simpleText']));
    return _nonEmpty(
        runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join());
  }

  static String? _query(Map renderer, String endpoint) =>
      _nonEmpty(_at(renderer, [endpoint, 'searchEndpoint', 'query']));

  static String? _params(Map renderer, String endpoint) =>
      _nonEmpty(_at(renderer, [endpoint, 'searchEndpoint', 'params']));
}
