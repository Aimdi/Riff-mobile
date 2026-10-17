import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/youtube_links.dart';

void main() {
  void opens(String link, YoutubeLinkKind kind, [String id = '']) {
    final l = youtubeLinkFrom(Uri.parse(link));
    expect(l.kind, kind, reason: link);
    expect(l.id, id, reason: link);
  }

  test('a video plays, however its link is written', () {
    const id = 'dQw4w9WgXcQ';
    opens(
        'https://music.youtube.com/watch?v=$id&si=x', YoutubeLinkKind.song, id);
    opens('https://www.youtube.com/watch?v=$id&list=RDAMVM$id',
        YoutubeLinkKind.song, id);
    opens('https://youtu.be/$id', YoutubeLinkKind.song, id);
    opens('https://youtu.be/$id?si=abc', YoutubeLinkKind.song, id);
    // Only a moment in it: it used to do nothing.
    opens('https://youtu.be/$id?t=42', YoutubeLinkKind.song, id);
    opens('https://www.youtube.com/live/$id?feature=share',
        YoutubeLinkKind.song, id);
    opens('https://www.youtube.com/embed/$id', YoutubeLinkKind.song, id);
    opens('https://m.youtube.com/watch?v=$id', YoutubeLinkKind.song, id);
  });

  test('playlists, albums, artists and podcasts open their pages', () {
    opens('https://music.youtube.com/playlist?list=PLabc',
        YoutubeLinkKind.playlist, 'PLabc');
    opens('https://music.youtube.com/playlist?list=OLAK5uy_album',
        YoutubeLinkKind.playlist, 'OLAK5uy_album');
    opens('https://music.youtube.com/browse/MPREb_abc', YoutubeLinkKind.album,
        'MPREb_abc');
    opens('https://music.youtube.com/browse/VLPLabc', YoutubeLinkKind.playlist,
        'PLabc');
    opens('https://music.youtube.com/browse/MPSPPLshow',
        YoutubeLinkKind.playlist, 'MPSPPLshow');
    opens('https://music.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw',
        YoutubeLinkKind.artist, 'UCuAXFkgsw1L7xaCfnd5JJOw');
    opens('https://music.youtube.com/browse/UCuAXFkgsw1L7xaCfnd5JJOw',
        YoutubeLinkKind.artist, 'UCuAXFkgsw1L7xaCfnd5JJOw');
  });

  test('a channel by its name is looked up', () {
    opens('https://www.youtube.com/@RickAstleyYT', YoutubeLinkKind.handle,
        'RickAstleyYT');
    opens('https://www.youtube.com/@RickAstleyYT/videos',
        YoutubeLinkKind.handle, 'RickAstleyYT');
    opens('https://www.youtube.com/c/RickAstley', YoutubeLinkKind.handle,
        'RickAstley');
    opens('https://www.youtube.com/user/RickAstleyVEVO', YoutubeLinkKind.handle,
        'RickAstleyVEVO');
  });

  test('a Short is no song; the rest is nothing to open', () {
    opens('https://youtube.com/shorts/dQw4w9WgXcQ', YoutubeLinkKind.short);
    for (final link in [
      'https://music.youtube.com',
      'https://music.youtube.com/watch',
      'https://music.youtube.com/playlist',
      'https://www.youtube.com/channel/notachannel',
      'https://music.youtube.com/browse/FEmusic_home',
      'https://youtu.be/',
      'https://www.youtube.com/feed/subscriptions',
      'https://example.com/watch?v=dQw4w9WgXcQ',
    ]) {
      opens(link, YoutubeLinkKind.invalid);
    }
  });

  test("a link's moment, as YouTube's Share at 1:23 writes it", () {
    Duration at(String link) => youtubeLinkStart(Uri.parse(link));
    expect(
        at('https://youtu.be/dQw4w9WgXcQ?t=83'), const Duration(seconds: 83));
    expect(at('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=83s'),
        const Duration(seconds: 83));
    expect(at('https://youtu.be/dQw4w9WgXcQ?t=1m23s'),
        const Duration(minutes: 1, seconds: 23));
    expect(at('https://youtu.be/dQw4w9WgXcQ?t=1h2m3s'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(at('https://www.youtube.com/embed/dQw4w9WgXcQ?start=90'),
        const Duration(seconds: 90));
    expect(at('https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=45'),
        const Duration(seconds: 45));
    // None, or none that reads as a time.
    expect(at('https://youtu.be/dQw4w9WgXcQ'), Duration.zero);
    expect(at('https://youtu.be/dQw4w9WgXcQ?t=soon'), Duration.zero);
  });
}
