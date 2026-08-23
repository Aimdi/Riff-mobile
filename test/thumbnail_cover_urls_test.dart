import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/models/thumbnail.dart';

void main() {
  group('Thumbnail.coverUrls', () {
    test('empty and the Harmony placeholder are skipped', () {
      expect(Thumbnail.coverUrls(''), isEmpty);
      expect(Thumbnail.coverUrls('   '), isEmpty);
      expect(Thumbnail.coverUrls(Playlist.thumbPlaceholderUrl), isEmpty);
    });

    test('googleusercontent upgrade is tried before the stored original', () {
      const raw =
          'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj';
      final urls = Thumbnail.coverUrls(raw);
      expect(urls, isNotEmpty);
      expect(urls.first, contains('w720-h720'));
      expect(urls.contains(raw), isTrue);
      expect(urls.lastIndexOf(raw), greaterThan(0));
      // -p smart-crop 404s on some podcast art; keep a crop-free retry.
      expect(urls.any((u) => u.contains('w720-h720') && !u.contains('-p-')),
          isTrue);
    });

    test('Apple 3000 art falls back through 1400, then the stored file', () {
      const raw =
          'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/aa/bb/cc/mza_1/3000x3000bb.jpg';
      final urls = Thumbnail.coverUrls(raw);
      expect(urls.any((u) => u.contains('1400x1400')), isTrue);
      expect(urls.contains(raw), isTrue);
      expect(urls.any((u) => u.contains('400x400')), isTrue);
    });

    test('plain https artwork is returned as-is', () {
      const raw = 'https://assets.economist.com/podcasts/cover.jpg';
      expect(Thumbnail.coverUrls(raw), [raw]);
    });

    test('http artwork also tries https', () {
      const raw = 'http://feeds.example.com/art.jpg';
      final urls = Thumbnail.coverUrls(raw);
      expect(urls, contains(raw));
      expect(urls, contains('https://feeds.example.com/art.jpg'));
    });
  });
}
