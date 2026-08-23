import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/chapter_marks.dart';

void main() {
  test('drops the 0:00 intro and the episode end', () {
    final marks = podcastChapterMarks([
      PodcastChapter(startSec: 0, title: 'Intro'),
      PodcastChapter(startSec: 60, title: 'A'),
      PodcastChapter(startSec: 180, title: 'B'),
      PodcastChapter(startSec: 300, title: 'End'),
    ], 300);
    expect(marks, [60 / 300, 180 / 300]);
  });

  test('no duration or no inner chapters → no marks (one straight segment)', () {
    expect(podcastChapterMarks(const [], 120), isEmpty);
    expect(
      podcastChapterMarks(
          [PodcastChapter(startSec: 0, title: 'Whole show')], 120),
      isEmpty,
    );
    expect(
      podcastChapterMarks(
          [PodcastChapter(startSec: 30, title: 'A')], 0),
      isEmpty,
    );
  });
}
