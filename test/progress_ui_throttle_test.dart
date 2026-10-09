import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/progress_ui_throttle.dart';

void main() {
  test('throttles dense ticks but always passes seeks', () {
    final t = ProgressUiThrottle(
      minInterval: const Duration(milliseconds: 100),
      jumpThreshold: const Duration(milliseconds: 350),
    );
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);

    expect(
      t.shouldUpdate(
        position: const Duration(seconds: 1),
        previousUiPosition: Duration.zero,
        now: t0,
      ),
      isTrue,
    );
    expect(
      t.shouldUpdate(
        position: const Duration(milliseconds: 1040),
        previousUiPosition: const Duration(seconds: 1),
        now: t0.add(const Duration(milliseconds: 40)),
      ),
      isFalse,
    );
    expect(
      t.shouldUpdate(
        position: const Duration(milliseconds: 1120),
        previousUiPosition: const Duration(seconds: 1),
        now: t0.add(const Duration(milliseconds: 120)),
      ),
      isTrue,
    );
    // Scrub / seek jump bypasses the interval.
    expect(
      t.shouldUpdate(
        position: const Duration(seconds: 40),
        previousUiPosition: const Duration(milliseconds: 1120),
        now: t0.add(const Duration(milliseconds: 130)),
      ),
      isTrue,
    );
  });

  test('buffered: unchanged never refreshes, small moves are batched', () {
    final t = BufferedUiThrottle();
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    const b = Duration(seconds: 20);

    expect(
        t.shouldUpdate(buffered: b, previousUiBuffered: Duration.zero, now: t0),
        isTrue);
    // ExoPlayer video mode: the same buffer with every position tick.
    expect(
        t.shouldUpdate(
            buffered: b,
            previousUiBuffered: b,
            now: t0.add(const Duration(seconds: 5))),
        isFalse);
    // A small move right after a refresh waits for the next one.
    expect(
        t.shouldUpdate(
            buffered: b + const Duration(milliseconds: 250),
            previousUiBuffered: b,
            now: t0.add(const Duration(milliseconds: 100))),
        isFalse);
    expect(
        t.shouldUpdate(
            buffered: b + const Duration(milliseconds: 250),
            previousUiBuffered: b,
            now: t0.add(const Duration(milliseconds: 250))),
        isTrue);
    // A big jump (seek, new source) shows at once.
    expect(
        t.shouldUpdate(
            buffered: const Duration(minutes: 3),
            previousUiBuffered: b,
            now: t0.add(const Duration(milliseconds: 260))),
        isTrue);
  });
}
