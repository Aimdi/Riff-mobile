import '/models/album.dart';

/// The artist's other releases for "More by …" under an album, as Spotify,
/// Apple Music and YouTube Music list them: from [artist] (what
/// MusicServices.getArtist returns), its albums, then its singles and EPs,
/// without the album open ([currentBrowseId], or by [currentTitle] when it
/// was opened by another id) or repeats; at most [max].
List<Album> moreByArtistAlbums(
    Map<String, dynamic> artist, String currentBrowseId,
    {String? currentTitle, int max = 12}) {
  final seen = {currentBrowseId};
  final title = currentTitle?.trim().toLowerCase();
  final out = <Album>[];
  // Singles by the shelf's name now ("Singles & EPs") or before.
  for (final key in const ['Albums', 'Singles & EPs', 'Singles']) {
    final shelf = artist[key];
    final content = shelf is Map ? shelf['content'] : null;
    if (content is! List) continue;
    for (final a in content) {
      if (a is Album &&
          a.browseId.isNotEmpty &&
          a.title.trim().toLowerCase() != title &&
          seen.add(a.browseId)) {
        out.add(a);
        if (out.length >= max) return out;
      }
    }
  }
  return out;
}
