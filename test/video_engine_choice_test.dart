import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/video_engine.dart';

void main() {
  test('ExoPlayer is the default whenever it exists', () {
    expect(
        chooseVideoEngine(
            preference: null, exoAvailable: true, mpvAvailable: true),
        'exo');
    expect(
        chooseVideoEngine(
            preference: 'exo', exoAvailable: true, mpvAvailable: true),
        'exo');
  });

  test('mpv only when chosen and bundled', () {
    expect(
        chooseVideoEngine(
            preference: 'mpv', exoAvailable: true, mpvAvailable: true),
        'mpv');
    // Lite APK has no mpv: a saved "mpv" falls back to ExoPlayer.
    expect(
        chooseVideoEngine(
            preference: 'mpv', exoAvailable: true, mpvAvailable: false),
        'exo');
  });

  test('no engine at all', () {
    expect(
        chooseVideoEngine(
            preference: 'exo', exoAvailable: false, mpvAvailable: false),
        isNull);
    expect(
        chooseVideoEngine(
            preference: 'exo', exoAvailable: false, mpvAvailable: true),
        'mpv');
  });
}
