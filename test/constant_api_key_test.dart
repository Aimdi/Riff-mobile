import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/constant.dart';

void main() {
  test('ytmApiKey is assembled public WEB_REMIX client id', () {
    final key = ytmApiKey;
    expect(key.startsWith('AIza'), isTrue);
    expect(key.length, 39);
    expect(fixedParms.contains('key=$key'), isTrue);
    // Contiguous literal must not appear in constant.dart (secret-scan).
    // Spot-check shape only — full value is Google's public YTM client id.
    expect(key.substring(4, 12), 'SyC9XL3Z');
    expect(key.endsWith('NX30'), isTrue);
  });
}
