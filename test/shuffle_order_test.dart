import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/shuffle_order.dart';

/// Songs as "artist:n": [count] each of [artists].
List<String> _songs(Map<String, int> artists) => [
      for (final MapEntry(key: artist, value: count) in artists.entries)
        for (var i = 0; i < count; i++) '$artist:$i'
    ];

String _artist(String song) => song.split(':').first;

/// How often the same artist plays twice in a row in [order].
int _repeats(List<String> order) => [
      for (var i = 1; i < order.length; i++)
        if (_artist(order[i]) == _artist(order[i - 1])) 1
    ].length;

/// Average [_repeats] over [runs] shuffles of [songs] made by [shuffle].
double _averageRepeats(List<String> songs,
    List<String> Function(List<String> songs, Random random) shuffle,
    {int runs = 400}) {
  var total = 0;
  for (var seed = 0; seed < runs; seed++) {
    total += _repeats(shuffle([...songs], Random(seed)));
  }
  return total / runs;
}

void main() {
  test('appending keeps the played prefix and the current track in place', () {
    final result = appendToShuffleOrder(['a', 'b', 'c', 'd', 'e'], 1, ['f']);

    // Nothing dropped: the old bug returned a length-5 list missing 'b'.
    expect(result.length, 6);
    expect(result.toSet(), {'a', 'b', 'c', 'd', 'e', 'f'});

    // Played prefix + currently playing track survive at their indices, so
    // currentShuffleIndex still points at the track that is playing.
    expect(result.take(2).toList(), ['a', 'b']);
  });

  test('empty order just shuffles the new ids', () {
    final result = appendToShuffleOrder([], 0, ['a', 'b', 'c']);
    expect(result.toSet(), {'a', 'b', 'c'});
    expect(result.length, 3);
  });

  test('appending while on the last entry keeps the whole order', () {
    final result = appendToShuffleOrder(['a', 'b', 'c'], 2, ['d', 'e']);
    expect(result.length, 5);
    expect(result.take(3).toList(), ['a', 'b', 'c']);
    expect(result.toSet(), {'a', 'b', 'c', 'd', 'e'});
  });

  test('out-of-range currentIndex is clamped instead of throwing', () {
    final result = appendToShuffleOrder(['a', 'b'], 7, ['c']);
    expect(result.length, 3);
    expect(result.take(2).toList(), ['a', 'b']);
    expect(result.last, 'c');

    final negative = appendToShuffleOrder(['a', 'b'], -3, ['c']);
    expect(negative.length, 3);
    expect(negative.first, 'a');
    expect(negative.toSet(), {'a', 'b', 'c'});
  });

  test('repeated appends never desync the order length', () {
    var order = ['a', 'b', 'c'];
    for (var i = 0; i < 10; i++) {
      order = appendToShuffleOrder(order, 1, ['new$i']);
    }
    expect(order.length, 13);
    expect(order.toSet().length, 13);
  });

  group('balanced shuffle (Spotify, Apple Music)', () {
    List<String> balanced(List<String> songs, Random random) =>
        balancedShuffle(songs, _artist, random: random);
    List<String> plain(List<String> songs, Random random) =>
        songs..shuffle(random);

    test('every song once, whatever the mix', () {
      final songs = _songs({'a': 6, 'b': 3, 'c': 3, 'd': 1, 'e': 1});
      for (var seed = 0; seed < 50; seed++) {
        final order = balancedShuffle(songs, _artist, random: Random(seed));
        expect(order.length, songs.length);
        expect(order.toSet(), songs.toSet());
      }
    });

    test("an artist's songs are spread out, not side by side", () {
      for (final mix in [
        {'a': 6, 'b': 3, 'c': 3, 'd': 1, 'e': 1, 'f': 1},
        {'a': 4, 'b': 4},
        {'a': 5, 'b': 5, 'c': 5, 'd': 5},
        {'a': 10, 'b': 2, 'c': 2, 'd': 2, 'e': 2, 'f': 2},
      ]) {
        final songs = _songs(mix);
        final spread = _averageRepeats(songs, balanced);
        final chance = _averageRepeats(songs, plain);
        // Far fewer of the same artist twice in a row than by chance.
        expect(spread, lessThan(chance * 0.35),
            reason: '$mix: $spread / $chance');
      }
    });

    test('songs without an artist are each their own', () {
      final order =
          balancedShuffle(['x', 'y', 'z'], (_) => '', random: Random(1));
      expect(order.toSet(), {'x', 'y', 'z'});
    });

    test("one artist's songs still come in a new order", () {
      final songs = _songs({'a': 8});
      final orders = {
        for (var seed = 0; seed < 20; seed++)
          balancedShuffle(songs, _artist, random: Random(seed)).join(',')
      };
      expect(orders.length, greaterThan(10));
    });

    test('the first artist credited is whose a song is', () {
      expect(
          shuffleArtistOf(const MediaItem(
              id: 'x', title: 'X', artist: 'Daft Punk & Pharrell Williams')),
          'Daft Punk');
      expect(shuffleArtistOf(const MediaItem(id: 'y', title: 'Y')), '');
    });

    test('added songs spread among those still to play', () {
      final order = appendToShuffleOrder(
          ['a:0', 'b:0', 'a:1', 'a:2'], 1, ['a:3', 'b:1', 'b:2'],
          artistOf: _artist, random: Random(3));
      expect(order.take(2).toList(), ['a:0', 'b:0']);
      expect(order.toSet(), {'a:0', 'b:0', 'a:1', 'a:2', 'a:3', 'b:1', 'b:2'});
    });
  });
}
