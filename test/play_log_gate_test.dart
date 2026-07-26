import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/play_log_gate.dart';

void main() {
  test('accepts a new id once and rejects consecutive re-emissions', () {
    final gate = PlayLogGate();

    // First emission of a track: a real play.
    expect(gate.accept('a'), isTrue);
    // Handler re-emits the same item (duration discovery at queue index 0,
    // reorder, shuffle, removal) - must not count again.
    expect(gate.accept('a'), isFalse);
    expect(gate.accept('a'), isFalse);

    // Moving to a different track is a new play.
    expect(gate.accept('b'), isTrue);
    expect(gate.accept('b'), isFalse);

    // Explicit re-tap of the same queue row counts again after a reset.
    gate.reset();
    expect(gate.accept('b'), isTrue);
    expect(gate.accept('b'), isFalse);
  });

  test('returning to a previous track counts as a new play', () {
    final gate = PlayLogGate();

    expect(gate.accept('a'), isTrue);
    expect(gate.accept('b'), isTrue);
    expect(gate.accept('a'), isTrue);
  });
}
