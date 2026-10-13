import 'package:audio_service/audio_service.dart';

/// Custom media-session action behind the heart on the notification, lock
/// screen, Android 13+ media controls and Android Auto.
const likeActionName = 'toggleLike';

/// Heart icons for that action (android/app/src/main/res/drawable, kept in
/// release builds by res/raw/keep.xml).
const likedIcon = 'drawable/ic_notif_favorite';
const notLikedIcon = 'drawable/ic_notif_favorite_border';

/// The controls the media session offers for what is playing.
///
/// Podcast episodes: skip back · play/pause · skip forward · next.
/// Everything else: previous · play/pause · next, and for music a heart
/// that likes / unlikes the song (like Spotify, YouTube Music and
/// Metrolist). The compact notification keeps showing the first three.
List<MediaControl> nowPlayingControls({
  required bool podcast,
  required bool playing,
  required bool canLike,
  required bool liked,
  required String likeLabel,
  required String unlikeLabel,
}) {
  final playPause = playing ? MediaControl.pause : MediaControl.play;
  if (podcast) {
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
    if (canLike)
      MediaControl.custom(
        androidIcon: liked ? likedIcon : notLikedIcon,
        label: liked ? unlikeLabel : likeLabel,
        name: likeActionName,
      ),
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
