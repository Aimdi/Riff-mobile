import 'package:audio_service/audio_service.dart';

/// Custom media-session action behind the heart on the notification, lock
/// screen, Android 13+ media controls and Android Auto.
const likeActionName = 'toggleLike';

/// Heart icons for that action (android/app/src/main/res/drawable, kept in
/// release builds by res/raw/keep.xml).
const likedIcon = 'drawable/ic_notif_favorite';
const notLikedIcon = 'drawable/ic_notif_favorite_border';

/// Custom actions behind shuffle and repeat, as Android Auto shows them
/// (YouTube Music's and Spotify's car screens have both): shuffle turns on
/// or off, repeat goes off → all → one → off, as the player's button does.
const shuffleActionName = 'toggleShuffle';
const repeatActionName = 'cycleRepeat';

/// Their icons, a dot under the glyph while on (one colour, as the
/// notification and the car draw them; kept like the hearts).
const shuffleOffIcon = 'drawable/ic_notif_shuffle';
const shuffleOnIcon = 'drawable/ic_notif_shuffle_on';
const repeatOffIcon = 'drawable/ic_notif_repeat';
const repeatAllIcon = 'drawable/ic_notif_repeat_on';
const repeatOneIcon = 'drawable/ic_notif_repeat_one_on';

/// The controls the media session offers for what is playing.
///
/// Podcast episodes and audiobooks ([longForm]): skip back · play/pause ·
/// skip forward · next. Everything else: previous · play/pause · next, and
/// for music a heart that likes / unlikes the song (like Spotify, YouTube
/// Music and Metrolist), then shuffle ([shuffle]) and repeat ([repeat]: 0
/// off, 1 all, 2 one), each [shuffleLabel] / [repeatLabel] saying what a
/// press does. The compact notification keeps showing the first three.
List<MediaControl> nowPlayingControls({
  required bool longForm,
  required bool playing,
  required bool canLike,
  required bool liked,
  required String likeLabel,
  required String unlikeLabel,
  bool shuffle = false,
  int repeat = 0,
  String shuffleLabel = '',
  String repeatLabel = '',
}) {
  final playPause = playing ? MediaControl.pause : MediaControl.play;
  if (longForm) {
    return [
      MediaControl.rewind,
      playPause,
      MediaControl.fastForward,
      MediaControl.skipToNext,
    ];
  }
  return [
    MediaControl.skipToPrevious,
    playPause,
    MediaControl.skipToNext,
    if (canLike) ...[
      MediaControl.custom(
        androidIcon: liked ? likedIcon : notLikedIcon,
        label: liked ? unlikeLabel : likeLabel,
        name: likeActionName,
      ),
      MediaControl.custom(
        androidIcon: shuffle ? shuffleOnIcon : shuffleOffIcon,
        label: shuffleLabel,
        name: shuffleActionName,
      ),
      MediaControl.custom(
        androidIcon: switch (repeat) {
          1 => repeatAllIcon,
          2 => repeatOneIcon,
          _ => repeatOffIcon,
        },
        label: repeatLabel,
        name: repeatActionName,
      ),
    ],
  ];
}

/// Whether the playing item ([currentId]) is liked, for the heart: the
/// app's own answer ([reportedId] / [reportedLiked], sent when it checks
/// or toggles) wins over what storage says, since the toggle saves in the
/// background.
bool nowPlayingLiked({
  required String? currentId,
  required String? reportedId,
  required bool reportedLiked,
  required bool Function(String id) stored,
}) {
  if (currentId == null) return false;
  if (reportedId == currentId) return reportedLiked;
  return stored(currentId);
}
