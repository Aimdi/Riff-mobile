import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/scrobble_rules.dart';

MediaItem _song(
        {Duration? duration,
        String id = 'dQw4w9WgXcQ',
        Map<String, dynamic>? extras}) =>
    MediaItem(id: id, title: 't', duration: duration, extras: extras);

void main() {
  test('half the track or four minutes, whichever comes first', () {
    final threeMin = _song(duration: const Duration(minutes: 3));
    expect(
        shouldScrobble(item: threeMin, listened: const Duration(seconds: 89)),
        isFalse);
    expect(
        shouldScrobble(item: threeMin, listened: const Duration(seconds: 90)),
        isTrue);

    final tenMin = _song(duration: const Duration(minutes: 10));
    expect(shouldScrobble(item: tenMin, listened: const Duration(minutes: 3)),
        isFalse);
    expect(shouldScrobble(item: tenMin, listened: const Duration(minutes: 4)),
        isTrue);
  });

  test('explicit total wins over the item duration', () {
    final item = _song(duration: const Duration(minutes: 10));
    expect(
        shouldScrobble(
            item: item,
            listened: const Duration(seconds: 61),
            total: const Duration(minutes: 2)),
        isTrue);
  });

  test('unknown length needs four minutes; short tracks never count', () {
    expect(shouldScrobble(item: _song(), listened: const Duration(minutes: 3)),
        isFalse);
    expect(shouldScrobble(item: _song(), listened: const Duration(minutes: 4)),
        isTrue);
    expect(
        shouldScrobble(
            item: _song(duration: const Duration(seconds: 25)),
            listened: const Duration(seconds: 25)),
        isFalse);
  });

  test('podcasts and audiobooks are not scrobbled', () {
    const long = Duration(hours: 1);
    expect(
        shouldScrobble(
            item: _song(id: 'podcast_1', duration: long), listened: long),
        isFalse);
    expect(
        shouldScrobble(
            item: _song(id: 'abs_1', duration: long), listened: long),
        isFalse);
  });
}
