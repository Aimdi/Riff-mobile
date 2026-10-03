/// How the app's stored podcast and playlist data maps to records of the
/// Riff sync format (docs/sync-format.md), and back. Pure Dart: the
/// adapters in sync_collections.dart do the Hive reads and writes.
library;

import 'sync_merge.dart';

/// Drop nulls and empty strings, so stored data with and without a value
/// hashes the same.
Map<String, dynamic> compactData(Map<String, dynamic> m) => {
      for (final e in m.entries)
        if (e.value != null &&
            !(e.value is String && (e.value as String).isEmpty))
          e.key: e.value
    };

int? _positiveInt(Object? v) {
  final n = v is num ? v.toInt() : null;
  return n != null && n > 0 ? n : null;
}

bool _isLocalUrl(String? u) =>
    u != null && (u.startsWith('file://') || u.startsWith('/'));

/// RSS episodes have `podcast_<n>` ids; YouTube episodes use the video id.
bool isRssEpisodeId(String id) => id.startsWith('podcast_');

// ── Episodes ──────────────────────────────────────────────────────────

/// `podcast.episodes` data for an in-progress row of `PodcastProgress`.
Map<String, dynamic> episodeDataFromProgress(String id, Map row) {
  final url = row['url']?.toString();
  return compactData({
    'positionMs': _positiveInt(row['positionMs']) ?? 0,
    'durationMs': _positiveInt(row['durationMs']),
    'played': false,
    'title': row['title']?.toString(),
    'show': row['artist']?.toString(),
    'artUri': row['artUri']?.toString(),
    'feedUrl': row['feedUrl']?.toString(),
    'enclosureUrl': _isLocalUrl(url) ? null : url,
    if (!isRssEpisodeId(id)) 'videoId': id,
  });
}

/// `podcast.episodes` data for a finished episode (`PodcastPlayed`).
Map<String, dynamic> episodeDataPlayed(String id) => {
      'positionMs': 0,
      'played': true,
      if (!isRssEpisodeId(id)) 'videoId': id,
    };

/// The `PodcastProgress` row for an in-progress record, on top of the row
/// the app already had (show notes, chapters and such stay).
Map<String, dynamic> progressRowFromEpisode(
    String id, Map<String, dynamic> data, int updatedAt, Map? previous) {
  final prev = previous == null
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(previous);
  String? s(String k) {
    final v = data[k];
    return v is String && v.isNotEmpty ? v : null;
  }

  return {
    ...prev,
    'id': id,
    'title': s('title') ?? prev['title'] ?? '',
    'artist': s('show') ?? prev['artist'],
    'artUri': s('artUri') ?? prev['artUri'],
    'url': s('enclosureUrl') ?? prev['url'],
    'feedUrl': s('feedUrl') ?? prev['feedUrl'],
    'positionMs': _positiveInt(data['positionMs']) ?? 0,
    'durationMs': _positiveInt(data['durationMs']) ?? prev['durationMs'] ?? 0,
    'updatedAt': updatedAt,
  };
}

/// Riff Mobile's id for an RSS episode, as the feed parser makes it
/// (`podcast_` + the hash of the item's guid, or of the enclosure URL when
/// the item has no guid).
String riffRssEpisodeId({String? guid, required String enclosureUrl}) {
  final g = guid?.trim();
  return 'podcast_${(g == null || g.isEmpty ? enclosureUrl : g).hashCode}';
}

/// Our id for an episode a record names, or null when it can't be told.
/// `url:` ids (from apps that can't compute ours) are turned into ours.
String? localEpisodeId(String id, {Map? data}) {
  if (!id.startsWith('url:')) return id;
  final url = id.substring(4);
  if (url.isEmpty) return null;
  final guid = data?['guid'];
  return riffRssEpisodeId(
      guid: guid is String ? guid : null, enclosureUrl: url);
}

/// Give `url:` episode records our ids: the same data and time under our
/// id (unless a later version is there already) and a tombstone at the
/// same time for the `url:` id. Returns the new map, or null when there
/// were none.
Map<String, SyncRecord>? adoptForeignEpisodeIds(
    Map<String, SyncRecord> records, String device) {
  if (!records.keys.any((k) => k.startsWith('url:'))) return null;
  final out = Map<String, SyncRecord>.from(records);
  for (final e in records.entries) {
    if (!e.key.startsWith('url:') || e.value.deleted) continue;
    final ours = localEpisodeId(e.key, data: e.value.data);
    if (ours == null) continue;
    final existing = out[ours];
    if (existing == null || compareRecords(e.value, existing) > 0) {
      out[ours] = SyncRecord(
          updatedAt: e.value.updatedAt,
          device: e.value.device,
          data: e.value.data,
          extra: e.value.extra);
    }
    out[e.key] =
        SyncRecord.tombstone(updatedAt: e.value.updatedAt, device: device);
  }
  return out;
}

// ── Bookmarks ─────────────────────────────────────────────────────────

/// `podcast.bookmarks` data for a stored bookmark (its `toJson`), with the
/// episode's feed and audio URLs so other apps can find it.
Map<String, dynamic> bookmarkData(Map<String, dynamic> json) {
  final data = Map<String, dynamic>.from(json)
    ..remove('id')
    ..remove('updatedAt');
  final ep = json['episode'];
  final extras = ep is Map ? ep['extras'] : null;
  if (extras is Map) {
    final feed = extras['feedUrl'];
    final url = extras['remoteUrl'] ?? extras['url'];
    if (feed is String && feed.isNotEmpty) data['feedUrl'] = feed;
    if (url is String && url.isNotEmpty && !_isLocalUrl(url)) {
      data['enclosureUrl'] = url;
    }
  }
  return compactData(data);
}

// ── Manual segments ───────────────────────────────────────────────────

String segmentRecordId(String episodeId, String segmentId) =>
    '$episodeId#$segmentId';

/// Episode and segment id of a segment record id (split at the last `#`).
({String episodeId, String segmentId})? parseSegmentRecordId(String id) {
  final i = id.lastIndexOf('#');
  if (i <= 0 || i == id.length - 1) return null;
  return (episodeId: id.substring(0, i), segmentId: id.substring(i + 1));
}

/// When a manual segment was made, from its `m_<ms>` id.
int? segmentCreatedAt(String segmentId) => segmentId.startsWith('m_')
    ? _positiveInt(int.tryParse(segmentId.substring(2)))
    : null;

// ── Playlists ─────────────────────────────────────────────────────────

/// A song of `library.playlists` from a stored song map (the app's
/// MediaItem JSON): `thumbnails` becomes `thumbnailUrl`, `duration`
/// becomes `durationSec`, empty fields go.
Map<String, dynamic> syncSongFromStored(Map stored) {
  final m = <String, dynamic>{
    for (final e in stored.entries) '${e.key}': e.value
  };
  final thumbs = m.remove('thumbnails');
  if (thumbs is List && thumbs.isNotEmpty && thumbs.first is Map) {
    final url = (thumbs.first as Map)['url'];
    if (url is String && url.isNotEmpty && url != 'null') {
      m['thumbnailUrl'] = url;
    }
  }
  final d = m.remove('duration');
  if (d is num && d > 0) m['durationSec'] = d.toInt();
  // A downloaded file's path means nothing on another device.
  if (m['url'] is String && _isLocalUrl(m['url'] as String)) m.remove('url');
  return compactData(m);
}

/// The stored song map for a synced song.
Map<String, dynamic> storedSongFromSync(Map song) {
  final m = <String, dynamic>{
    for (final e in song.entries) '${e.key}': e.value
  };
  final url = m.remove('thumbnailUrl');
  if (url is String && url.isNotEmpty) {
    m['thumbnails'] = [
      {'url': url}
    ];
  }
  final d = m.remove('durationSec');
  m['duration'] = d is num && d > 0 ? d.toInt() : null;
  return m;
}

/// Favourites' playlist id.
const favoritesPlaylistId = 'LIBFAV';

/// Kind of a playlist entry of `LibraryPlaylists`, or null for ones that
/// aren't synced here (Piped playlists, generated mixes, and Favourites,
/// which sync song by song in `library.favorites`).
String? playlistKind(Map json) {
  if (json['isPipedPlaylist'] == true) return null;
  if (json['kind'] != null) return null;
  if ('${json['playlistId'] ?? ''}' == favoritesPlaylistId) return null;
  return json['isCloudPlaylist'] == false ? 'local' : 'youtube';
}

String? _thumb(Map json) {
  final t = json['thumbnails'];
  if (t is List && t.isNotEmpty && t.first is Map) {
    final u = (t.first as Map)['url'];
    if (u is String && u.isNotEmpty) return u;
  }
  final u = json['thumbnailUrl'];
  return u is String && u.isNotEmpty ? u : null;
}

/// `library.playlists` data for a playlist entry and its stored songs.
Map<String, dynamic> playlistData(Map json, String kind, List<Map> songs) =>
    compactData({
      'title': '${json['title'] ?? ''}',
      'description': json['description']?.toString(),
      'thumbnailUrl': _thumb(json),
      'kind': kind,
      'songs': kind == 'youtube'
          ? const <Map>[]
          : [for (final s in songs) syncSongFromStored(s)],
    });

/// The `LibraryPlaylists` entry for a synced playlist.
Map<String, dynamic> playlistEntryFromSync(String id, Map data) => {
      'title': '${data['title'] ?? ''}',
      'playlistId': id,
      'description': data['description']?.toString() ?? 'Library Playlist',
      if (data['thumbnailUrl'] case final String url when url.isNotEmpty)
        'thumbnails': [
          {'url': url}
        ],
      'itemCount': null,
      'isPipedPlaylist': false,
      'isCloudPlaylist': data['kind'] == 'youtube',
    };
