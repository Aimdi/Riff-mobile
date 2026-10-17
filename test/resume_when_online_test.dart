import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/resume_when_online.dart';

void main() {
  final at = DateTime(2026, 10, 14, 8);

  test('goes on where it stopped, once, when the connection is back', () {
    final resume = ResumeWhenOnline();
    expect(resume.take(at, playing: false), isNull);

    resume.stopped('song1', const Duration(seconds: 42), at);
    expect(resume.isWaiting, isTrue);
    expect(resume.take(at.add(const Duration(minutes: 3)), playing: false),
        (id: 'song1', position: const Duration(seconds: 42)));
    // Once.
    expect(resume.isWaiting, isFalse);
    expect(resume.take(at.add(const Duration(minutes: 4)), playing: false),
        isNull);
  });

  test('not after you did something else, nor long after', () {
    final resume = ResumeWhenOnline();
    resume.stopped('song1', Duration.zero, at);
    resume.cancel();
    expect(resume.take(at, playing: false), isNull);

    // Something plays already (a downloaded song you started).
    resume.stopped('song1', Duration.zero, at);
    expect(resume.take(at, playing: true), isNull);
    expect(resume.isWaiting, isFalse);

    // Back after more than ten minutes: music starting by itself would
    // surprise.
    resume.stopped('song1', Duration.zero, at);
    expect(resume.take(at.add(const Duration(minutes: 11)), playing: false),
        isNull);
    resume.stopped('song1', Duration.zero, at);
    expect(resume.take(at.add(const Duration(minutes: 10)), playing: false),
        isNotNull);
  });
}
