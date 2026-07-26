import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/shuffle_order.dart';

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
}
