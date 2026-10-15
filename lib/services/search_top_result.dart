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
    final runs = (nav(card, ['subtitle', 'runs']) as List?) ?? const [];
    final kindText = runs.isEmpty ? '' : '${runs.first['text'] ?? ''}'.trim();
    final videoId = nav(card, ['onTap', 'watchEndpoint', 'videoId']);
    final videoType = nav(card, ['onTap', ...navigation_video_type]);
    // The label says what it is in English; the endpoints in any language.
    final kind = _labels.contains(kindText.toLowerCase())
        ? kindText.toLowerCase()
        : searchKindOf(
            pageType:
                nav(card, [...n_title, ...navigation_browse, ...page_type]) ??
                    nav(card, ['onTap', 'browseEndpoint', ...page_type]),
            videoType: videoType,
            watch: videoId != null);
    if (kind == null) return null;
    return searchResultItem(
      kind: kind,
      title: title,
      runs: runs,
      thumbs: nav(card, thumbnails),
      browseId: (nav(card, [...n_title, ...navigation_browse_id]) ??
              nav(card, ['onTap', 'browseEndpoint', 'browseId']))
          ?.toString(),
      videoId: videoId?.toString(),
      videoType: videoType?.toString(),
      explicit: nav(card, _explicitBadge) != null,
      audioPlaylistId: nav(card, [
        'buttons',
        0,
        'buttonRenderer',
        'command',
        'watchPlaylistEndpoint',
        'playlistId'
      ])?.toString(),
    );
  }

  static const _labels = {
    'song',
    'video',
    'artist',
    'album',
    'single',
    'ep',
    'playlist',
    'podcast',
  };

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

/// What a search row or card opens, by its endpoints (its label is in the
/// app's language): 'song', 'video', 'episode', 'artist', 'album',
/// 'playlist' or 'podcast' by its page's type ([pageType]), or its video's
/// ([videoType]) when it plays ([watch]); null for anything else (a
/// profile).
String? searchKindOf(
    {Object? pageType, Object? videoType, bool watch = false}) {
  switch (pageType) {
    case 'MUSIC_PAGE_TYPE_ARTIST':
      return 'artist';
    case 'MUSIC_PAGE_TYPE_ALBUM':
    case 'MUSIC_PAGE_TYPE_AUDIOBOOK':
      return 'album';
    case 'MUSIC_PAGE_TYPE_PLAYLIST':
      return 'playlist';
    case 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE':
      return 'podcast';
  }
  if (!watch) return null;
  return switch (videoType) {
    'MUSIC_VIDEO_TYPE_ATV' => 'song',
    'MUSIC_VIDEO_TYPE_PODCAST_EPISODE' => 'episode',
    _ => 'video',
  };
}

/// A search result of [kind] as the overview keeps its kind: a MediaItem
/// (a song or a video), an Artist, an Album (a single, an EP) or a Playlist
/// (a podcast too), from what YouTube Music shows of it: its [title] and
/// its subtitle's [runs] (the kind's label, then who it's by, …). Null when
/// it lacks what it needs, or is another kind (an episode).
Object? searchResultItem({
  required String kind,
  required String title,
  required List runs,
  Object? thumbs,
  String? browseId,
  String? videoId,
  String? videoType,
  bool explicit = false,
  String? audioPlaylistId,
}) {
  if (title.isEmpty) return null;
  final kindText = runs.isEmpty ? '' : '${runs.first['text'] ?? ''}'.trim();
  final details = runs.length > 2 ? runs.sublist(2) : const [];
  final description = runs.map((r) => '${r['text'] ?? ''}').join();
  switch (kind) {
    case 'song':
    case 'video':
      if (videoId == null) return null;
      return MediaItemBuilder.fromJson({
        'title': title,
        'resultType': kind,
        'videoId': videoId,
        'videoType': videoType,
        'thumbnails': thumbs,
        ...parseSongRuns(details),
        if (explicit) 'isExplicit': true,
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
        'audioPlaylistId': audioPlaylistId,
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
