import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart';

void main() {
  group('normalizeSearchCategory', () {
    test('maps common shelf titles', () {
      expect(MusicServices.normalizeSearchCategory('Songs'), 'Songs');
      expect(MusicServices.normalizeSearchCategory('Videos'), 'Videos');
      expect(MusicServices.normalizeSearchCategory('Albums'), 'Albums');
      expect(MusicServices.normalizeSearchCategory('Artists'), 'Artists');
      expect(MusicServices.normalizeSearchCategory('Community playlists'),
          'Community playlists');
      expect(MusicServices.normalizeSearchCategory('Featured playlists'),
          'Featured playlists');
      expect(MusicServices.normalizeSearchCategory('Podcasts'), 'Podcasts');
      expect(MusicServices.normalizeSearchCategory('Episodes'), 'Episodes');
    });

    test('normalizes loose labels', () {
      expect(MusicServices.normalizeSearchCategory('Top songs'), 'Songs');
      expect(MusicServices.normalizeSearchCategory('Music videos'), 'Videos');
      expect(MusicServices.normalizeSearchCategory('Playlists'),
          'Community playlists');
    });
  });
}
