import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/now_playing_controls.dart';

void main() {
  List<MediaControl> controls({
    bool longForm = false,
    bool playing = true,
    bool canLike = true,
    bool liked = false,
  }) =>
      nowPlayingControls(
        longForm: longForm,
        playing: playing,
        canLike: canLike,
        liked: liked,
        likeLabel: 'Add to Favorites',
        unlikeLabel: 'Remove from Favorites',
      );

  group('nowPlayingControls', () {
    test('music: previous, pause, next, then the heart', () {
      final c = controls();
      expect(c.map((m) => m.action), [
        MediaAction.skipToPrevious,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.custom,
      ]);
      // The compact notification (indices 0-2) is unchanged.
      expect(c.last.customAction?.name, likeActionName);
    });

    test('the heart shows the like state and says what a tap does', () {
      final notLiked = controls(liked: false).last;
      expect(notLiked.androidIcon, notLikedIcon);
      expect(notLiked.label, 'Add to Favorites');
      final liked = controls(liked: true).last;
      expect(liked.androidIcon, likedIcon);
      expect(liked.label, 'Remove from Favorites');
    });

    test('paused: play instead of pause', () {
      expect(controls(playing: false)[1].action, MediaAction.play);
    });

    test('no heart where liking does not apply', () {
      expect(controls(canLike: false).map((m) => m.action), [
        MediaAction.skipToPrevious,
        MediaAction.pause,
        MediaAction.skipToNext,
      ]);
    });

    test('podcasts and audiobooks skip back / forward, with no heart', () {
      expect(controls(longForm: true).map((m) => m.action), [
        MediaAction.rewind,
        MediaAction.pause,
        MediaAction.fastForward,
        MediaAction.skipToNext,
      ]);
    });
  });

  group('nowPlayingLiked', () {
    bool stored(String id) => id == 'saved';

    test("the app's report for the playing song wins over storage", () {
      // Just toggled: storage hasn't caught up yet.
      expect(
          nowPlayingLiked(
              currentId: 'saved',
              reportedId: 'saved',
              reportedLiked: false,
              stored: stored),
          isFalse);
      expect(
          nowPlayingLiked(
              currentId: 'new',
              reportedId: 'new',
              reportedLiked: true,
              stored: stored),
          isTrue);
    });

    test('a report about another song is ignored', () {
      expect(
          nowPlayingLiked(
              currentId: 'saved',
              reportedId: 'previous',
              reportedLiked: false,
              stored: stored),
          isTrue);
    });

    test('nothing playing: not liked', () {
      expect(
          nowPlayingLiked(
              currentId: null,
              reportedId: null,
              reportedLiked: true,
              stored: stored),
          isFalse);
    });
  });
}
