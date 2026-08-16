import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/radio_continuation.dart';

void main() {
  group('radioShouldFetchContinuation', () {
    test('does not fire when radio is off', () {
      expect(
        radioShouldFetchContinuation(
          radioOn: false,
          inFlight: false,
          queueLength: 1,
          currentIndex: 0,
          isLastTrack: true,
        ),
        isFalse,
      );
    });

    test('does not fire while a fetch is in flight', () {
      expect(
        radioShouldFetchContinuation(
          radioOn: true,
          inFlight: true,
          queueLength: 1,
          currentIndex: 0,
          isLastTrack: true,
        ),
        isFalse,
      );
    });

    test('fires on the last track', () {
      expect(
        radioShouldFetchContinuation(
          radioOn: true,
          inFlight: false,
          queueLength: 10,
          currentIndex: 9,
          isLastTrack: true,
        ),
        isTrue,
      );
    });

    test('fires when 3 or fewer songs remain after current', () {
      expect(
        radioShouldFetchContinuation(
          radioOn: true,
          inFlight: false,
          queueLength: 8,
          currentIndex: 4,
          isLastTrack: false,
        ),
        isTrue,
      );
      expect(
        radioShouldFetchContinuation(
          radioOn: true,
          inFlight: false,
          queueLength: 8,
          currentIndex: 5,
          isLastTrack: false,
        ),
        isTrue,
      );
    });

    test('does not fire when more than 3 songs remain', () {
      expect(
        radioShouldFetchContinuation(
          radioOn: true,
          inFlight: false,
          queueLength: 8,
          currentIndex: 3,
          isLastTrack: false,
        ),
        isFalse,
      );
    });
  });
}
