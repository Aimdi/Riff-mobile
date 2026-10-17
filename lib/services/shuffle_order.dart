import 'dart:math';

import 'package:audio_service/audio_service.dart';

import '/services/ban_service.dart';

/// Pure list math for maintaining the shuffle order when items are appended
/// to the play queue.
///
/// The played prefix — everything up to and including the track at
/// [currentIndex] — is preserved in place, so the id of the track playing right
/// now keeps its slot and [currentIndex] stays valid. Only the not-yet-played
/// tail is re-shuffled together with [newIds].
///
/// With [artistOf] (an id's artist) the tail is shuffled as
/// [balancedShuffle] does, each artist's songs spread out.
List<String> appendToShuffleOrder(
    List<String> order, int currentIndex, List<String> newIds,
    {String Function(String id)? artistOf, Random? random}) {
  List<String> shuffled(List<String> ids) => artistOf == null
      ? (ids..shuffle(random))
      : balancedShuffle(ids, artistOf, random: random);
  if (order.isEmpty) {
    return shuffled([...newIds]);
  }
  final head = currentIndex.clamp(0, order.length - 1);
  final tail = shuffled(order.sublist(head + 1)..addAll(newIds));
  return [...order.take(head + 1), ...tail];
}

/// [items] shuffled as Spotify shuffles (and Apple Music): each artist's
/// songs are spread out across the whole list, each in its own stretch of
/// it, rather than wherever chance drops them, two or three in a row.
/// [artistOf] says whose an item is; items without one count as each
/// their own. [first] (the song playing) leads, and the song after it is
/// by someone else when it can be.
List<T> balancedShuffle<T extends Object>(
    Iterable<T> items, String Function(T item) artistOf,
    {Random? random, T? first}) {
  final rng = random ?? Random();
  final byArtist = <String, List<T>>{};
  var unnamed = 0;
  for (final item in items) {
    final artist = artistOf(item).trim().toLowerCase();
    byArtist
        .putIfAbsent(artist.isEmpty ? '\u0000${unnamed++}' : artist, () => [])
        .add(item);
  }
  final placed = <(double, T)>[];
  for (final songs in byArtist.values) {
    songs.shuffle(rng);
    // An artist's n songs, one in each n-th of the list: from a random
    // start in the first, then a step further each, give or take a little
    // so the artists don't fall into a fixed pattern.
    final step = 1 / songs.length;
    var at = rng.nextDouble() * step;
    for (final song in songs) {
      placed.add((at + (rng.nextDouble() - 0.5) * step * 0.2, song));
      at += step;
    }
  }
  placed.sort((a, b) => a.$1.compareTo(b.$1));
  final order = [
    if (first != null) first,
    for (final (_, item) in placed) item
  ];
  final artists = [
    for (final item in order) artistOf(item).trim().toLowerCase()
  ];
  _parted(order, artists);
  return order;
}

/// How far ahead [_parted] looks for a song to swap in.
const _partWindow = 8;

/// Where the same artist still plays twice in a row in [order] (an artist
/// with half the list or more leaves gaps the spreading can't fill), swaps
/// in a song a little further on by someone else, when that makes no new
/// pair where it came from. [artists] follows [order].
void _parted<T>(List<T> order, List<String> artists) {
  bool same(int i, int j) => artists[i].isNotEmpty && artists[i] == artists[j];
  for (var i = 1; i < order.length; i++) {
    if (!same(i, i - 1)) continue;
    final end = (i + _partWindow).clamp(0, order.length - 1);
    for (var j = i + 1; j <= end; j++) {
      if (artists[j] == artists[i - 1]) continue;
      // j goes to i (between i-1 and i+1), i goes to j (between j-1, j+1).
      final fitsAtI = j == i + 1 || artists[j] != artists[i + 1];
      final fitsAtJ = (j - 1 == i || artists[i] != artists[j - 1]) &&
          (j + 1 >= order.length || artists[i] != artists[j + 1]);
      if (!fitsAtI || !fitsAtJ) continue;
      final item = order[i];
      order[i] = order[j];
      order[j] = item;
      final artist = artists[i];
      artists[i] = artists[j];
      artists[j] = artist;
      break;
    }
  }
}

/// Whose [song] is, for [balancedShuffle]: the first artist credited.
String shuffleArtistOf(MediaItem song) =>
    BanService.primaryArtist(song) ?? song.artist ?? '';
