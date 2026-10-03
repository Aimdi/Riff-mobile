import 'dart:ui' show Color;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:hive/hive.dart';

/// Longest show notes kept per cached Inbox episode (the full notes come
/// back with the next refresh).
const inboxCacheNotesLimit = 1500;

/// Most episodes kept.
const inboxCacheLimit = 250;

/// A cached Inbox episode as plain values.
Map<String, dynamic> inboxEpisodeToJson(MediaItem e) {
  final extras = <String, dynamic>{
    for (final x in (e.extras ?? const <String, dynamic>{}).entries)
      if (x.value is String || x.value is num || x.value is bool)
        x.key: x.value,
  };
  final notes = extras['description'];
  if (notes is String && notes.length > inboxCacheNotesLimit) {
    extras['description'] = notes.substring(0, inboxCacheNotesLimit);
  }
  return {
    'id': e.id,
    'title': e.title,
    if (e.artist != null) 'artist': e.artist,
    if (e.artUri != null) 'artUri': e.artUri.toString(),
    if (e.duration != null) 'durationMs': e.duration!.inMilliseconds,
    'extras': extras,
  };
}

/// Null for anything that isn't a cached episode.
MediaItem? inboxEpisodeFromJson(dynamic j) {
  if (j is! Map) return null;
  final id = j['id'];
  if (id is! String || id.isEmpty) return null;
  final dur = j['durationMs'];
  final art = j['artUri'];
  final extras = j['extras'];
  return MediaItem(
    id: id,
    title: '${j['title'] ?? ''}',
    artist: j['artist']?.toString(),
    duration: dur is int && dur > 0 ? Duration(milliseconds: dur) : null,
    artUri: art is String ? Uri.tryParse(art) : null,
    extras: {
      if (extras is Map) ...Map<String, dynamic>.from(extras),
      'isPodcast': true,
    },
  );
}

/// The merged Inbox, kept on the phone so the Podcasts tab opens on it
/// straight away (box `PodcastInboxCache`), then refreshes behind it.
class PodcastInboxCache {
  PodcastInboxCache._();

  static const box = 'PodcastInboxCache';
  static const _key = 'inbox';

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  /// The stored Inbox when it was built from [subsKey], with its age.
  static ({List<MediaItem> items, DateTime at})? load(String subsKey) {
    final raw = _box?.get(_key);
    if (raw is! Map || raw['subs'] != subsKey) return null;
    final list = raw['items'];
    final at = raw['at'];
    if (list is! List || at is! int) return null;
    return (
      items: [
        for (final j in list)
          if (inboxEpisodeFromJson(j) case final e?) e
      ],
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  static Future<void> save(List<MediaItem> items, String subsKey,
      {DateTime? now}) async {
    final b = _box;
    if (b == null) return;
    try {
      await b.put(_key, {
        'subs': subsKey,
        'at': (now ?? DateTime.now()).millisecondsSinceEpoch,
        'items': [
          for (final e in items.take(inboxCacheLimit)) inboxEpisodeToJson(e)
        ],
      });
    } catch (_) {}
  }
}

/// Background tint for the podcast player from a show's artwork colour:
/// dark enough for white text, not garish.
Color podcastPlayerTint(Color dominant) {
  final hsl = HSLColor.fromColor(dominant);
  return hsl
      .withLightness(hsl.lightness.clamp(0.06, 0.16))
      .withSaturation(hsl.saturation.clamp(0.0, 0.55))
      .toColor();
}
