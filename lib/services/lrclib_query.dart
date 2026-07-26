/// Pure query-parameter builder for the LRCLIB exact-match endpoint
/// (`https://lrclib.net/api/get`).
///
/// Kept free of Flutter/Dio/Hive imports so it can be unit-tested directly.
///
/// `/api/get` is an EXACT match lookup: every parameter sent must match the
/// stored track. Sending an `album_name` we do not actually know (most search,
/// radio and watch-playlist items carry no album) guarantees a miss, so the
/// key is omitted entirely when the album is null, empty or whitespace.
///
/// Values are returned unencoded — pass the map to Dio's `queryParameters`
/// so `&`, `?`, `#` and friends are percent-encoded correctly.
Map<String, dynamic> buildLrclibGetParams({
  required String artist,
  required String title,
  String? album,
  required int durationSec,
}) {
  final params = <String, dynamic>{
    'artist_name': artist.trim(),
    'track_name': title.trim(),
  };

  final trimmedAlbum = album?.trim() ?? '';
  if (trimmedAlbum.isNotEmpty) {
    params['album_name'] = trimmedAlbum;
  }

  params['duration'] = durationSec;
  return params;
}

/// Base endpoint for the LRCLIB exact-match lookup.
const String lrclibGetUrl = 'https://lrclib.net/api/get';
