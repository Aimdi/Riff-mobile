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
}
