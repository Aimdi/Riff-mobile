import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/now_playing_controls.dart';

void main() {
  List<MediaControl> controls({
    bool longForm = false,
    bool playing = true,
    bool canLike = true,
    bool liked = false,
    bool shuffle = false,
    int repeat = 0,
  }) =>
      nowPlayingControls(
        longForm: longForm,
        playing: playing,
        canLike: canLike,
        liked: liked,
        likeLabel: 'Add to Favorites',
        unlikeLabel: 'Remove from Favorites',
        shuffle: shuffle,
        repeat: repeat,
        shuffleLabel: 'Shuffle label',
        repeatLabel: 'Repeat label',
      );

  MediaControl named(List<MediaControl> c, String name) =>
      c.singleWhere((m) => m.customAction?.name == name);

  group('nowPlayingControls', () {
    test('music: previous, pause, next, then the heart, shuffle and repeat',
        () {
      final c = controls();
      expect(c.map((m) => m.action), [
        MediaAction.skipToPrevious,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.custom,
        MediaAction.custom,
        MediaAction.custom,
      ]);
      // The compact notification (indices 0-2) is unchanged; the heart
      // comes first of the rest (Android 13's controls show two of them).
      expect(c.skip(3).map((m) => m.customAction?.name),
          [likeActionName, shuffleActionName, repeatActionName]);
    });

    test('the heart shows the like state and says what a tap does', () {
      final notLiked = named(controls(liked: false), likeActionName);
      expect(notLiked.androidIcon, notLikedIcon);
      expect(notLiked.label, 'Add to Favorites');
      final liked = named(controls(liked: true), likeActionName);
      expect(liked.androidIcon, likedIcon);
      expect(liked.label, 'Remove from Favorites');
    });

    test('shuffle and repeat show their state, and say what a press does', () {
      expect(named(controls(), shuffleActionName).androidIcon, shuffleOffIcon);
      expect(named(controls(shuffle: true), shuffleActionName).androidIcon,
          shuffleOnIcon);
      expect(named(controls(), shuffleActionName).label, 'Shuffle label');
      expect([
        for (final r in [0, 1, 2])
          named(controls(repeat: r), repeatActionName).androidIcon
      ], [
        repeatOffIcon,
        repeatAllIcon,
        repeatOneIcon
      ]);
      expect(named(controls(), repeatActionName).label, 'Repeat label');
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

    List<MediaControl> episode({bool starred = false}) => nowPlayingControls(
          longForm: true,
          playing: true,
          canLike: false,
          liked: false,
          likeLabel: '',
          unlikeLabel: '',
          podcast: true,
          starred: starred,
          starLabel: 'Star episode',
          unstarLabel: 'Unstar episode',
          markPlayedLabel: 'Mark as played',
        );

    test("an episode's star and Mark as played after its skips", () {
      final c = episode();
      expect(c.take(4).map((m) => m.action), [
        MediaAction.rewind,
        MediaAction.pause,
        MediaAction.fastForward,
        MediaAction.skipToNext,
      ]);
      expect(c.skip(4).map((m) => m.customAction?.name),
          [starActionName, markPlayedActionName]);
      expect(named(c, markPlayedActionName).androidIcon, markPlayedIcon);
      expect(named(c, markPlayedActionName).label, 'Mark as played');
    });

    test('the star shows whether the episode is starred', () {
      final not = named(episode(starred: false), starActionName);
      expect(not.androidIcon, notStarredIcon);
      expect(not.label, 'Star episode');
      final starred = named(episode(starred: true), starActionName);
      expect(starred.androidIcon, starredIcon);
      expect(starred.label, 'Unstar episode');
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
