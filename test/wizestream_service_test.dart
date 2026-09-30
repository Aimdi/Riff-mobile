import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/wizestream_service.dart';

Playlist _show(String id) =>
    Playlist(title: 'Show', playlistId: id, thumbnailUrl: '', kind: 'podcast');

void main() {
  group('WizeStream.watchUrlFor', () {
    test('YouTube episode ids become watch links', () {
      expect(
        WizeStream.watchUrlFor(
            const MediaItem(id: 'dQw4w9WgXcQ', title: 'Episode')),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(
        WizeStream.watchUrlFor(const MediaItem(id: 'a-b_c1D2e3F', title: 'x')),
        'https://www.youtube.com/watch?v=a-b_c1D2e3F',
      );
    });

    test('RSS, Audiobookshelf and odd ids have no link', () {
      for (final id in [
        'podcast_123456',
        'abs_item_1',
        'short',
        'https://example.com/a.mp3',
        'dQw4w9WgXcQX',
      ]) {
        expect(WizeStream.watchUrlFor(MediaItem(id: id, title: 'x')), isNull,
            reason: id);
      }
    });
  });

  group('WizeStream.showUrlFor', () {
    test('YouTube Music podcast playlists open as playlists', () {
      expect(WizeStream.showUrlFor(_show('MPSPPLabcdefghijKLMNOP')),
          'https://www.youtube.com/playlist?list=PLabcdefghijKLMNOP');
      expect(WizeStream.showUrlFor(_show('PLabcdefghijKLMNOP')),
          'https://www.youtube.com/playlist?list=PLabcdefghijKLMNOP');
    });

    test('channels open as channels', () {
      expect(WizeStream.showUrlFor(_show('UCabcdefghijklmnopqrstuv')),
          'https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv');
    });

    test('RSS feeds and album ids have no link', () {
      expect(WizeStream.showUrlFor(_show('https://feeds.example.com/rss')),
          isNull);
      expect(WizeStream.showUrlFor(_show('MPREb_abc')), isNull);
    });
  });
}
