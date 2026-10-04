import 'dart:math';

import 'spotify_import_service.dart';

/// Spotify radio from the user's own listening: Spotify no longer gives
/// apps recommendations or related artists, so the mix is drawn from top
/// tracks, recent plays and Liked Songs, with at most [maxPerArtist] songs
/// by any artist and the same artist never twice in a row when it can be
/// helped.

String primaryArtistOf(SpotifyTrackRef t) =>
    t.artists.split(',').first.trim().toLowerCase();

/// Tracks of [lists] in order, each once (by id, else title and artist).
List<SpotifyTrackRef> mergeUnique(List<List<SpotifyTrackRef>> lists) {
  final seen = <String>{};
  return [
    for (final l in lists)
      for (final t in l)
        if (seen.add(t.id.isNotEmpty
            ? t.id
            : '${t.title.toLowerCase()}|${primaryArtistOf(t)}'))
          t
  ];
}

/// [ordered] with at most [max] songs per primary artist.
List<SpotifyTrackRef> capPerArtist(List<SpotifyTrackRef> ordered, int max) {
  final counts = <String, int>{};
  return [
    for (final t in ordered)
      if ((counts[primaryArtistOf(t)] =
              (counts[primaryArtistOf(t)] ?? 0) + 1) <=
          max)
        t
  ];
}

/// Reorder so the same artist doesn't play twice in a row where another
/// song can go in between (keeps the order otherwise).
List<SpotifyTrackRef> spreadArtists(List<SpotifyTrackRef> list) {
  final rest = [...list];
  final out = <SpotifyTrackRef>[];
  while (rest.isNotEmpty) {
    final last = out.isEmpty ? null : primaryArtistOf(out.last);
    var i = rest.indexWhere((t) => primaryArtistOf(t) != last);
    if (i < 0) i = 0;
    out.add(rest.removeAt(i));
  }
  return out;
}

/// A radio of up to [size] songs.
///
/// Without a seed: top tracks lead, mixed with recent plays and Liked
/// Songs. With [seed] (radio from a song): the song first, then songs by
/// its artist, then by artists sharing a genre with it ([genresByArtist],
/// lower-case artist name → genres, from top and followed artists), then
/// the rest.
List<SpotifyTrackRef> buildSpotifyRadio({
  required List<SpotifyTrackRef> top,
  List<SpotifyTrackRef> recent = const [],
  List<SpotifyTrackRef> liked = const [],
  Map<String, Set<String>> genresByArtist = const {},
  SpotifyTrackRef? seed,
  int size = 50,
  int maxPerArtist = 3,
  Random? random,
}) {
  final rnd = random ?? Random();
  final topShuffled = [...top]..shuffle(rnd);
  final others = mergeUnique([recent, liked])..shuffle(rnd);
  // Interleave: two top tracks for every other one, so favourites lead
  // without crowding out the rest.
  final mixed = <SpotifyTrackRef>[];
  var a = 0, b = 0;
  while (a < topShuffled.length || b < others.length) {
    for (var k = 0; k < 2 && a < topShuffled.length; k++) {
      mixed.add(topShuffled[a++]);
    }
    if (b < others.length) mixed.add(others[b++]);
  }
  var pool = mergeUnique([mixed]);

  if (seed != null) {
    final seedArtist = primaryArtistOf(seed);
    final seedGenres = genresByArtist[seedArtist] ?? const <String>{};
    int rank(SpotifyTrackRef t) {
      final artist = primaryArtistOf(t);
      if (artist == seedArtist) return 0;
      final g = genresByArtist[artist];
      if (g != null && g.any(seedGenres.contains)) return 1;
      return 2;
    }

    final rest = pool.where((t) => t.id != seed.id || seed.id.isEmpty).toList();
    final indexed = [for (var i = 0; i < rest.length; i++) (i, rest[i])];
    indexed.sort((x, y) {
      final c = rank(x.$2).compareTo(rank(y.$2));
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    pool = mergeUnique([
      [seed],
      [for (final e in indexed) e.$2]
    ]);
    final capped = capPerArtist(pool, maxPerArtist);
    // The seed stays first; the rest is spread out.
    return [
      capped.first,
      ...spreadArtists(capped.skip(1).toList()),
    ].take(size).toList();
  }
  return spreadArtists(capPerArtist(pool, maxPerArtist)).take(size).toList();
}
