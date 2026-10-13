import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/now_playing_widget.dart';

const _green = Color(0xFF1DB954);
const _black = Color(0xFF000000);

Map<String, Object?> _args(MediaItem? item, {bool playing = false}) =>
    nowPlayingWidgetArgs(
      item: item,
      artPath: '/art.jpg',
      playing: playing,
      accent: _green,
      onAccent: _black,
      labels: const {'play': 'Play'},
    );

/// Lets the widget service's short wait (one update per burst) pass.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 500));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('what the widget shows', () {
    expect(
        _args(const MediaItem(id: 'a', title: ' Song ', artist: 'Artist'),
            playing: true),
        {
          'title': 'Song',
          'artist': 'Artist',
          'art': '/art.jpg',
          'playing': true,
          'accent': 0xFF1DB954,
          'onAccent': 0xFF000000,
          'play': 'Play',
        });
    // No artist (some episodes): the album.
    expect(
        _args(const MediaItem(id: 'b', title: 'Episode', album: 'Show'))[
            'artist'],
        'Show');
    // Nothing to play yet: no texts, no art.
    final none = _args(null);
    expect(none['title'], isNull);
    expect(none['artist'], isNull);
    expect(none['art'], isNull);
  });

  test('art it can read straight from a file', () {
    expect(nowPlayingLocalArt(Uri.file('/data/art.jpg')), '/data/art.jpg');
    expect(nowPlayingLocalArt(Uri.parse('/storage/cover.png')),
        '/storage/cover.png');
    expect(nowPlayingLocalArt(Uri.parse('https://example.com/a.jpg')), isNull);
    expect(nowPlayingLocalArt(null), isNull);
  });

  test('button labels in the app language', () {
    expect(nowPlayingWidgetLabels(), {
      'play': 'play',
      'pause': 'pause',
      'next': 'next',
      'previous': 'previous',
    });
  });

  group('follows the player', () {
    final sent = <Map<Object?, Object?>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void listen() =>
        messenger.setMockMethodCallHandler(NowPlayingWidget.channel, (call) {
          if (call.method == 'update') {
            sent.add(call.arguments as Map<Object?, Object?>);
          }
          return Future.value();
        });

    setUp(sent.clear);
    tearDown(() {
      NowPlayingWidget.stop();
      messenger.setMockMethodCallHandler(NowPlayingWidget.channel, null);
    });

    test('one update per change, none when nothing it shows changed', () async {
      listen();
      final handler = BaseAudioHandler();
      NowPlayingWidget.start(handler,
          artPath: (item) async => '/art/${item.id}.jpg');
      await _settle();
      // Riff is running, nothing to play yet.
      expect(sent, hasLength(1));
      expect(sent.last['title'], isNull);

      handler.mediaItem
          .add(const MediaItem(id: 'a', title: 'Song', artist: 'Artist'));
      handler.playbackState.add(PlaybackState(playing: true));
      await _settle();
      expect(sent, hasLength(2));
      expect(sent.last['title'], 'Song');
      expect(sent.last['art'], '/art/a.jpg');
      expect(sent.last['playing'], isTrue);

      // Its length came in: the widget doesn't show that.
      handler.mediaItem.add(const MediaItem(
          id: 'a',
          title: 'Song',
          artist: 'Artist',
          duration: Duration(minutes: 3)));
      await _settle();
      expect(sent, hasLength(2));

      handler.playbackState.add(PlaybackState(playing: false));
      await _settle();
      expect(sent, hasLength(3));
      expect(sent.last['playing'], isFalse);

      NowPlayingWidget.stop();
      handler.playbackState.add(PlaybackState(playing: true));
      await _settle();
      expect(sent, hasLength(3));
    });

    test('tries again when the channel wasn\'t there yet', () async {
      final handler = BaseAudioHandler();
      NowPlayingWidget.start(handler, artPath: (_) async => null);
      await _settle();
      expect(sent, isEmpty);

      listen();
      NowPlayingWidget.refresh();
      await _settle();
      expect(sent, hasLength(1));
    });
  });
}
