import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';

void main() {
  final chapters = parsePodcastChapters({
    'version': '1.2.0',
    'chapters': [
      {'startTime': 60, 'title': 'Two', 'img': 'https://example.com/two.jpg'},
      {'startTime': 0, 'title': 'One'},
      {'startTime': 120, 'title': 'Three', 'img': 'ftp://example.com/x.jpg'},
      {'startTime': 180, 'title': 'Four', 'img': ' https://example.com/4.png '},
      {'title': 'No start'},
      'junk',
    ],
  });

  test('chapters in order, with the art they have', () {
    expect(chapters.map((c) => c.title), ['One', 'Two', 'Three', 'Four']);
    expect(chapters.map((c) => c.imageUrl), [
      null,
      'https://example.com/two.jpg',
      null, // not a web image
      'https://example.com/4.png',
    ]);
  });

  test("the playing chapter's art, else none (the episode's shows)", () {
    expect(chapterArtAt(chapters, 10), isNull);
    expect(chapterArtAt(chapters, 60), 'https://example.com/two.jpg');
    expect(chapterArtAt(chapters, 119.9), 'https://example.com/two.jpg');
    expect(chapterArtAt(chapters, 150), isNull);
    expect(chapterArtAt(chapters, 4000), 'https://example.com/4.png');
    expect(chapterArtAt(const [], 10), isNull);
  });

  test('nothing to read', () {
    expect(parsePodcastChapters(null), isEmpty);
    expect(parsePodcastChapters({'chapters': 'x'}), isEmpty);
  });
}
