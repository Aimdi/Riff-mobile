import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_play.dart';

void main() {
  test('audiobook library tiles play on tap', () {
    expect(shouldPlayAudiobookOnTap(), isTrue);
  });

  test('playAudiobook no-ops without services', () async {
    expect(await playAudiobook(bookId: 'missing'), isFalse);
  });
}
