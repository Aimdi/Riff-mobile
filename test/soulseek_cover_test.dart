import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/soulseek/soulseek_client.dart';
import 'package:harmonymusic/services/soulseek/soulseek_cover_service.dart';
import 'package:harmonymusic/services/soulseek/soulseek_search.dart';

void main() {
  group('CoverLookupHint', () {
    test('uses query artist and title in song mode', () {
      const file = SoulseekFile(
        username: 'u',
        filename: r'@@u\Music\Misc\01 - Creep.flac',
        size: 1,
        hasFreeSlot: true,
        speed: 1,
      );
      final query = SoulseekQuery.parse(
        'Radiohead - Creep',
        SoulseekSearchMode.song,
      );
      final hint = CoverLookupHint.fromFile(file, query);
      expect(hint.artist, 'Radiohead');
      expect(hint.title, 'Creep');
      expect(hint.cacheKey, contains('radiohead'));
    });

    test('parses Artist - Album folder name', () {
      const file = SoulseekFile(
        username: 'u',
        filename: r'@@u\Music\Radiohead - OK Computer\01.flac',
        size: 1,
        hasFreeSlot: true,
        speed: 1,
      );
      final hint = CoverLookupHint.fromFile(file, null);
      expect(hint.artist, 'Radiohead');
      expect(hint.album, 'OK Computer');
    });

    test('infers artist from parent folder', () {
      const file = SoulseekFile(
        username: 'u',
        filename: r'@@u\Music\Daft Punk\Discovery\01.flac',
        size: 1,
        hasFreeSlot: true,
        speed: 1,
      );
      final hint = CoverLookupHint.fromFile(file, null);
      expect(hint.artist, 'Daft Punk');
      expect(hint.album, 'Discovery');
    });
  });
}
