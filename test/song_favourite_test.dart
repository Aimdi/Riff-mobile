import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/song_favourite.dart';

void main() {
  test('row heart ignores a second tap inside the debounce window', () {
    final first = DateTime(2026, 1, 1, 12, 0, 0);
    expect(shouldIgnoreHeartToggle(null, first), isFalse);
    expect(
      shouldIgnoreHeartToggle(
        first,
        first.add(const Duration(milliseconds: 399)),
      ),
      isTrue,
    );
    expect(
      shouldIgnoreHeartToggle(
        first,
        first.add(const Duration(milliseconds: 400)),
      ),
      isFalse,
    );
  });
}
