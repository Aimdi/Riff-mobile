import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';

void main() {
  test('storefrontFromLocale picks the region, not the script', () {
    const cases = {
      'en_US': 'us',
      'de_DE': 'de',
      'de-DE': 'de',
      'en_US.UTF-8': 'us',
      'ca_ES@valencia': 'es',
      'zh_Hans_CN': 'cn',
      'zh-Hant-TW': 'tw',
      'sr_Latn_RS': 'rs',
      'pt_BR': 'br',
      'en': 'us',
      'es_419': 'us',
      '': 'us',
      'C': 'us',
    };
    cases.forEach((locale, want) {
      expect(storefrontFromLocale(locale), want, reason: locale);
    });
  });
}
