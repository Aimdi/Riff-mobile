import 'package:audio_service/audio_service.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import 'nav_parser.dart';

/// The search's best match, as YouTube Music's search page shows it first
/// (its "Top result" card, a musicCardShelfRenderer; Spotify's search
/// too). YouTube Music leaves it out of the sections below it, so the
/// artist searched for wasn't among the overview's artists.
class SearchTopResult {
  SearchTopResult._();

  /// Where MusicServices.search keeps it among the overview's results.
  static const key = 'topResult';

  /// [card] as the overview keeps its other results: a MediaItem (a song
  /// or a video), an Artist, an Album (a single, an EP) or a Playlist (a
  /// podcast too). Null for anything else, or a card that can't be read.
  static Object? parse(Map card) {
    try {
      return _parse(card);
    } catch (_) {
      return null;
    }
  }

  static Object? _parse(Map card) {
    final title = '${nav(card, title_text) ?? ''}'.trim();
    if (title.isEmpty) return null;
    final runs = (nav(card, ['subtitle', 'runs']) as List?) ?? const [];
    final kindText = runs.isEmpty ? '' : '${runs.first['text'] ?? ''}'.trim();
    final kind = kindText.toLowerCase();
    final thumbs = nav(card, thumbnails);
    final browseId = (nav(card, [...n_title, ...navigation_browse_id]) ??
            nav(card, ['onTap', 'browseEndpoint', 'browseId']))
        ?.toString();
    final details = runs.length > 2 ? runs.sublist(2) : const [];
    final description = runs.map((r) => '${r['text'] ?? ''}').join();

    switch (kind) {
      case 'song':
      case 'video':
        final videoId = nav(card, ['onTap', 'watchEndpoint', 'videoId']);
        if (videoId == null) return null;
        return MediaItemBuilder.fromJson({
          'title': title,
          'resultType': kind,
          'videoId': '$videoId',
          'videoType': nav(card, ['onTap', ...navigation_video_type]),
          'thumbnails': thumbs,
          ...parseSongRuns(details),
          if (nav(card, _explicitBadge) != null) 'isExplicit': true,
        });
      case 'artist':
        if (browseId == null) return null;
        return Artist.fromJson({
          'artist': title,
          'browseId': browseId,
          'subscribers':
              details.isEmpty ? '' : '${details.last['text'] ?? ''}'.trim(),
          'thumbnails': thumbs,
        });
      case 'album':
      case 'single':
      case 'ep':
        if (browseId == null || !browseId.startsWith('MPRE')) return null;
        final info = parseSongRuns(details);
        return Album.fromJson({
          'title': title,
          'browseId': browseId,
          'artists': info['artists'],
          'year': info['year'],
          'type': kindText,
          'description': description,
          'audioPlaylistId': nav(card, [
            'buttons',
            0,
            'buttonRenderer',
            'command',
            'watchPlaylistEndpoint',
            'playlistId'
          ]),
          'thumbnails': thumbs,
        });
      case 'playlist':
      case 'podcast':
        if (browseId == null) return null;
        return Playlist.fromJson({
          'title': title,
          'playlistId': browseId,
          'browseId': browseId,
          'thumbnails': thumbs,
          'description': description,
          if (kind == 'podcast') 'kind': 'podcast',
        });
    }
    return null;
  }

  static const _explicitBadge = [
    'subtitleBadges',
    0,
    'musicInlineBadgeRenderer',
    'accessibilityData',
    'accessibilityData',
    'label'
  ];

  /// The overview section whose rows [item] is shown as.
  static String kindOf(Object item) => switch (item) {
        MediaItem(:final extras) => extras?['resultType'] == 'song' ||
                extras?['videoType'] == 'MUSIC_VIDEO_TYPE_ATV'
            ? 'Songs'
            : 'Videos',
        Artist() => 'Artists',
        Album() => 'Albums',
        Playlist(:final kind) =>
          kind == 'podcast' ? 'Podcasts' : 'Community playlists',
        _ => '',
      };

  /// [a] and [b] are the same result (the top one also in a section).
  static bool same(Object? a, Object? b) => switch ((a, b)) {
        (MediaItem a, MediaItem b) => a.id == b.id,
        (Artist a, Artist b) => a.browseId == b.browseId,
        (Album a, Album b) => a.browseId == b.browseId,
        (Playlist a, Playlist b) => a.playlistId == b.playlistId,
        _ => false,
      };
}
