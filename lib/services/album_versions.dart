import '/models/album.dart';
import 'nav_parser.dart';

/// An album's other versions (a deluxe edition, a remaster, the clean or
/// the explicit one), as YouTube Music's album page lists them under its
/// tracks ("Other versions") and Apple Music's does.
class AlbumVersions {
  const AlbumVersions(this.title, this.albums);

  /// What the page calls them, in its language ("Other versions").
  final String title;
  final List<Album> albums;

  /// The first carousel of albums under the album page's tracks
  /// ([response], a browse answer), without the album open
  /// ([currentBrowseId]); null when there's none. Rows that can't be read
  /// are left out, and a carousel that can't be read is no versions: it
  /// never costs the album its tracks.
  static AlbumVersions? fromAlbumPage(Object? response,
      {required String currentBrowseId}) {
    final sections = nav(response, [
      'contents',
      'twoColumnBrowseResultsRenderer',
      'secondaryContents',
      'sectionListRenderer',
      'contents'
    ]);
    if (sections is! List) return null;
    for (final section in sections) {
      final shelf =
          section is Map ? section['musicCarouselShelfRenderer'] : null;
      final items = shelf is Map ? shelf['contents'] : null;
      if (items is! List) continue;
      final seen = {currentBrowseId};
      final albums = <Album>[];
      for (final item in items) {
        final row = item is Map ? item['musicTwoRowItemRenderer'] : null;
        if (row is! Map) continue;
        try {
          final album = parseAlbum(row);
          if (album.browseId.startsWith('MPRE') && seen.add(album.browseId)) {
            albums.add(album);
          }
        } catch (_) {
          // An unreadable row: left out.
        }
      }
      if (albums.isEmpty) continue;
      final title = nav(shelf, [...carousel_title, 'text']);
      return AlbumVersions(title is String ? title.trim() : '', albums);
    }
    return null;
  }
}
