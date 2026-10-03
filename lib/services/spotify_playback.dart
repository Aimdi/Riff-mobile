import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '../models/playling_from.dart';
import '../ui/player/player_controller.dart';
import 'spotify_import_service.dart';

/// Positions of [length] tracks in the order to play them when starting at
/// [start]: from there to the end, or, with [shuffle], the tapped one first
/// and everything else shuffled.
List<int> spotifyPlayOrder(int length, int start,
    {bool shuffle = false, Random? random}) {
  if (length <= 0) return const [];
  final s = start.clamp(0, length - 1);
  if (!shuffle) return [for (var i = s; i < length; i++) i];
  final rest = [
    for (var i = 0; i < length; i++)
      if (i != s) i
  ]..shuffle(random ?? Random());
  return [s, ...rest];
}

/// Chunks of [list], [size] at a time.
List<List<T>> chunked<T>(List<T> list, int size) => [
      for (var i = 0; i < list.length; i += size)
        list.sublist(i, min(i + size, list.length))
    ];

enum SpotifyPlayResult { playing, nothingMatched, failed, superseded }

/// Plays Spotify tracks through Riff's own player: the first track that
/// matches starts at once, the rest are matched a few at a time and added
/// to the queue in order. Starting something else stops the filling.
class SpotifyPlayback {
  SpotifyPlayback._();

  /// The first tracks tried before giving up on finding something to play.
  static const firstTries = 6;
  static const batchSize = 8;

  static int _generation = 0;

  /// Tracks still being matched for the queue (for a progress hint).
  static final pending = 0.obs;

  /// Stop filling the queue from an earlier [play].
  static void cancel() {
    _generation++;
    pending.value = 0;
  }

  static Future<SpotifyPlayResult> play(
    List<SpotifyTrackRef> tracks, {
    int start = 0,
    bool shuffle = false,
    required String from,
  }) async {
    if (tracks.isEmpty || !Get.isRegistered<PlayerController>()) {
      return SpotifyPlayResult.failed;
    }
    final gen = ++_generation;
    if (!Get.isRegistered<SpotifyImportService>()) {
      Get.put(SpotifyImportService());
    }
    final importer = Get.find<SpotifyImportService>();
    final player = Get.find<PlayerController>();
    final order = spotifyPlayOrder(tracks.length, start, shuffle: shuffle);
    pending.value = order.length;

    MediaItem? first;
    var i = 0;
    while (first == null && i < order.length && i < firstTries) {
      first = await importer.resolveTrack(tracks[order[i]]);
      i++;
      pending.value = order.length - i;
    }
    if (gen != _generation) return SpotifyPlayResult.superseded;
    if (first == null) {
      pending.value = 0;
      return SpotifyPlayResult.nothingMatched;
    }
    final ok = await player.playPlayListSong([first], 0,
        playfrom: PlaylingFrom(type: PlaylingFromType.PLAYLIST, name: from));
    if (!ok) {
      pending.value = 0;
      return SpotifyPlayResult.failed;
    }

    final firstId = first.id;
    for (final chunk in chunked(order.sublist(i), batchSize)) {
      if (gen != _generation) return SpotifyPlayResult.superseded;
      final items = await importer
          .resolveTracksDetailed([for (final j in chunk) tracks[j]]);
      // Something else started playing meanwhile: leave its queue alone.
      if (gen != _generation ||
          !player.currentQueue.any((m) => m.id == firstId)) {
        if (gen == _generation) pending.value = 0;
        return SpotifyPlayResult.superseded;
      }
      final matched = items.whereType<MediaItem>().toList();
      if (matched.isNotEmpty) await player.enqueueSongList(matched);
      pending.value = (pending.value - chunk.length).clamp(0, order.length);
    }
    if (gen == _generation) pending.value = 0;
    return SpotifyPlayResult.playing;
  }
}
