import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

/// How long [songs] play together, as Spotify and Apple Music give an
/// album's or a playlist's length ("14 songs, 52 min"): when each one's
/// length is known, and they're a minute or more; null otherwise.
Duration? totalLength(Iterable<MediaItem> songs) {
  var total = Duration.zero;
  var any = false;
  for (final song in songs) {
    final length = song.duration;
    if (length == null || length <= Duration.zero) return null;
    total += length;
    any = true;
  }
  return any && total >= const Duration(minutes: 1) ? total : null;
}

/// [length] in whole minutes, with hours from an hour on: "52 min",
/// "1 h 12 min", "3 h".
String lengthLabel(Duration length) {
  final minutes = (length.inSeconds / 60).round();
  if (minutes < 60) {
    return 'lengthMinutes'.trParams({'minutes': '$minutes'});
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0
      ? 'lengthHours'.trParams({'hours': '$hours'})
      : 'lengthHoursMinutes'.trParams({'hours': '$hours', 'minutes': '$rest'});
}
