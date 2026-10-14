/// Spotify's Smart Shuffle: a playlist shuffled with songs like it mixed
/// in, each marked as a suggestion.
library;

import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import 'discovery/discovery_service.dart';
import 'discovery/discovery_types.dart';

/// A suggestion Smart Shuffle mixed in (not one of the playlist's own).
bool isSmartShufflePick(MediaItem song) => song.extras?['smartShuffle'] == true;

MediaItem markSmartShufflePick(MediaItem song) => DiscoveryService.withSource(
    song.copyWith(extras: {...?song.extras, 'smartShuffle': true}),
    DiscoverySource.smartShuffle);

/// [songs] shuffled, with one of [picks] after every [every] of them: none
/// of the playlist's own, none twice, at most one per [every] songs.
List<MediaItem> smartShuffleOrder(List<MediaItem> songs, List<MediaItem> picks,
    {int every = 3, Random? random}) {
  final shuffled = [...songs]..shuffle(random);
  final seen = {for (final s in songs) s.id};
  final extra = [
    for (final p in picks)
      if (seen.add(p.id)) markSmartShufflePick(p)
  ];
  final out = <MediaItem>[];
  var next = 0;
  for (var i = 0; i < shuffled.length; i++) {
    out.add(shuffled[i]);
    if ((i + 1) % every == 0 && next < extra.length) out.add(extra[next++]);
  }
  return out;
}

/// Suggestions for [songs]: songs like a few of them ([seeds], picked at
/// random) that you haven't heard; none of [songs] themselves. Empty when
/// there's no way to ask (offline, no discovery).
Future<List<MediaItem>> smartShufflePicks(List<MediaItem> songs,
    {int seeds = 3, Random? random}) async {
  if (songs.isEmpty || !Get.isRegistered<DiscoveryService>()) return const [];
  final discovery = Get.find<DiscoveryService>();
  // All at once, each given a few seconds: the menu waits on them.
  Future<List<MediaItem>> like(MediaItem seed) async {
    try {
      return await discovery
          .similarSongs(seed, limit: 10, unheardOnly: true)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline, or nothing like it: the other seeds may still answer.
      return const [];
    }
  }

  final batches = await Future.wait([
    for (final seed in ([...songs]..shuffle(random)).take(seeds)) like(seed)
  ]);
  final seen = {for (final s in songs) s.id};
  return [
    for (final batch in batches)
      for (final m in batch)
        if (seen.add(m.id)) m
  ]..shuffle(random);
}
