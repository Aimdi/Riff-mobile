import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '/services/device_file_tags.dart';
import '/services/device_music.dart';
import '/services/play_by_index_skip.dart';
import '/services/replay_gain.dart';

/// [song] is one YouTube doesn't measure, whose loudness may be its own
/// (ownLoudnessDb): a phone song, a music server's.
bool hasOwnLoudness(MediaItem song) =>
    DeviceMusic.isDeviceSong(song) || song.id.startsWith('cloud_');

/// The loudness of a song YouTube doesn't measure, from its ReplayGain: a
/// phone song's tags; what a music server measured of its song (kept with
/// it, else asked of [server]). As YouTube's loudnessDb, which loudness
/// normalization plays by; null when it has none, or is neither.
Future<double?> ownLoudnessDb(MediaItem song,
    {Future<ReplayGain?> Function(String serverSongId)? server}) async {
  ReplayGain? gain;
  if (DeviceMusic.isDeviceSong(song)) {
    gain = (await DeviceFileTags.forSong(song))?.replayGain;
  } else if (song.id.startsWith('cloud_')) {
    gain = ReplayGain.fromJson(song.extras?['replayGain']) ??
        await server?.call(cloudServerSongId(song.id));
  }
  final db = gain?.gain;
  return db == null ? null : ReplayGain.loudnessDb(db);
}

/// [value] when it comes within [wait]; else null at once, and [whenLate]
/// gets it once it comes (when it isn't null).
Future<T?> soonOrLate<T extends Object>(
    Future<T?> value, Duration wait, void Function(T value) whenLate) async {
  var late = false;
  final soon = await value.timeout(wait, onTimeout: () {
    late = true;
    return null;
  });
  if (late) {
    unawaited(value.then((v) {
      if (v != null) whenLate(v);
    }));
  }
  return soon;
}
