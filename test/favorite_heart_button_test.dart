import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/favorite_heart_button.dart';

void main() {
  test('medium press is between a tap and default long-press', () {
    final ms = FavoriteHeartButton.mediumPress.inMilliseconds;
    expect(ms, greaterThan(200));
    expect(ms, lessThan(500));
  });

  test('heart toggle debounce is longer than a double-tap gap', () {
    expect(
      FavoriteHeartButton.toggleDebounce.inMilliseconds,
      greaterThanOrEqualTo(300),
    );
  });
}
