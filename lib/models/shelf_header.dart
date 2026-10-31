/// What YouTube Music shows over a home shelf's title: a small line (its
/// "strapline": "Similar to", or your name over "Listen again") and a
/// picture (the artist's photo, round; your own; a cover).
class ShelfHeader {
  const ShelfHeader(
      {this.strapline,
      this.art,
      this.round = false,
      this.named = false,
      this.link,
      this.linkType});

  final String? strapline;

  /// The picture's address; null when the shelf has none.
  final String? art;

  /// An artist's or account's picture, drawn round.
  final bool round;

  /// The title is a name ("Nova Hart" under "Similar to", linked to its
  /// page), not a heading like "Listen again": it keeps its capitals.
  final bool named;

  /// The page the name opens on YouTube Music (a browse id), and what it
  /// is: 'artist' or 'album'.
  final String? link;
  final String? linkType;

  bool get isEmpty =>
      (strapline == null || strapline!.isEmpty) &&
      (art == null || art!.isEmpty);

  /// From the parser's map, or a cached shelf's; null when there's nothing.
  static ShelfHeader? fromJson(dynamic json) {
    if (json is! Map) return null;
    final h = ShelfHeader(
      strapline: _text(json['strapline']),
      art: _text(json['art']),
      round: json['round'] == true,
      named: json['named'] == true,
      link: _text(json['link']),
      linkType: _text(json['linkType']),
    );
    return h.isEmpty ? null : h;
  }

  static String? _text(dynamic v) {
    final s = v is String ? v.trim() : '';
    return s.isEmpty ? null : s;
  }

  Map<String, dynamic> toJson() => {
        if (strapline != null) 'strapline': strapline,
        if (art != null) 'art': art,
        if (round) 'round': true,
        if (named) 'named': true,
        if (link != null) 'link': link,
        if (linkType != null) 'linkType': linkType,
      };
}
