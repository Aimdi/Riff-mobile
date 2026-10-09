import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '/models/media_item_extras.dart';
import '/utils/helper.dart';
import 'podcast_segments.dart' show looksLikeYoutubeVideoId;
import 'podcast_service.dart';

/// Where an episode's transcript comes from, in priority order: the feed's
/// Podcasting 2.0 `<podcast:transcript>`, then YouTube captions for
/// YouTube-sourced episodes.
class TranscriptSource {
  const TranscriptSource.feed(this.url, this.type) : youtubeId = null;
  const TranscriptSource.youtube(String id)
      : youtubeId = id,
        url = '',
        type = '';

  final String url;
  final String type;
  final String? youtubeId;

  bool get isYoutube => youtubeId != null;

  /// Cache key: the feed URL, or `yt:<videoId>`.
  String get key => isYoutube ? 'yt:$youtubeId' : url;
}

/// The best transcript source for [item], or null when it has none we
/// know of. Podcast episodes only.
TranscriptSource? transcriptSourceFor(MediaItem? item) {
  if (item == null) return null;
  if (!item.isPodcastEpisode) return null;
  final extras = item.extras ?? const {};
  final url = '${extras['transcriptUrl'] ?? ''}'.trim();
  if (url.isNotEmpty) {
    return TranscriptSource.feed(url, '${extras['transcriptType'] ?? ''}');
  }
  if (looksLikeYoutubeVideoId(item.id)) return TranscriptSource.youtube(item.id);
  return null;
}

/// One caption track on offer: its language and whether YouTube made it.
typedef CaptionTrackChoice = ({String lang, bool auto});

/// Which caption track to use: a human-made one in the app language, then
/// an automatic one in it (that's the spoken language), then any human-made
/// track, then whatever there is. -1 when there are none.
int pickCaptionTrack(List<CaptionTrackChoice> tracks, String preferredLang) {
  if (tracks.isEmpty) return -1;
  final want = preferredLang.toLowerCase().split(RegExp('[-_]')).first;
  bool inLang(CaptionTrackChoice t) =>
      t.lang.toLowerCase().split(RegExp('[-_]')).first == want;
  for (final test in <bool Function(CaptionTrackChoice)>[
    (t) => !t.auto && inLang(t),
    (t) => t.auto && inLang(t),
    (t) => !t.auto,
  ]) {
    final i = tracks.indexWhere(test);
    if (i >= 0) return i;
  }
  return 0;
}

/// Lines whose text contains [query] (case-insensitive), in order.
List<int> transcriptMatches(List<PodcastTranscriptCue> cues, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return [
    for (var i = 0; i < cues.length; i++)
      if (cues[i].text.toLowerCase().contains(q) ||
          (cues[i].speaker?.toLowerCase().contains(q) ?? false))
        i
  ];
}

/// Character ranges of [query] inside [text], for highlighting.
List<(int, int)> matchRanges(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final lower = text.toLowerCase();
  final out = <(int, int)>[];
  var from = 0;
  while (true) {
    final i = lower.indexOf(q, from);
    if (i < 0) break;
    out.add((i, i + q.length));
    from = i + q.length;
  }
  return out;
}

/// Next / previous search hit, wrapping around. [current] is the index into
/// [count] hits (-1 when none is selected yet).
int stepMatch(int current, int count, {required bool forward}) {
  if (count <= 0) return -1;
  if (current < 0) return forward ? 0 : count - 1;
  return forward ? (current + 1) % count : (current - 1 + count) % count;
}

/// The first hit at or after the active line, so a search starts near
/// where you are listening instead of at the top.
int firstMatchFrom(List<int> matches, int activeLine) {
  if (matches.isEmpty) return -1;
  final i = matches.indexWhere((m) => m >= activeLine);
  return i < 0 ? 0 : i;
}

/// A stored transcript is usable when it has lines; they don't change, so
/// it never goes stale. Nothing is stored for a fetch that came back empty
/// (offline, server down), so that's retried next time.
bool transcriptCacheUsable(dynamic raw) =>
    raw is Map && raw['cues'] is List && (raw['cues'] as List).isNotEmpty;

/// Oldest cache keys beyond [keep] entries, to evict.
List<String> transcriptKeysToEvict(Map<String, int> savedAt, int keep) {
  if (savedAt.length <= keep) return const [];
  final byAge = savedAt.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return [for (final e in byAge.take(savedAt.length - keep)) e.key];
}

/// A loaded transcript and what it came from.
class LoadedTranscript {
  const LoadedTranscript(this.cues, {this.youtube = false, this.auto = false});
  final List<PodcastTranscriptCue> cues;
  final bool youtube;
  final bool auto;

  bool get timed => cues.isNotEmpty && cues.first.timed;
}

/// Loads, parses and caches podcast transcripts (box `PodcastTranscripts`),
/// and knows which episodes have one so the player can hide the button
/// when there's nothing to show.
class PodcastTranscriptService {
  PodcastTranscriptService._();

  static const box = 'PodcastTranscripts';
  static const _keep = 40;

  /// Parsed transcripts kept in memory, the most recently used last. One
  /// long episode's is thousands of lines; older ones reload from the box.
  static const _memoryKeep = 4;

  /// YouTube video id → whether captions exist. Filled by [probe].
  static final youtubeAvailable = <String, bool>{}.obs;

  static final _memory = <String, LoadedTranscript>{};
  static final _inFlight = <String, Future<LoadedTranscript>>{};

  static void _remember(String key, LoadedTranscript t) {
    _memory.remove(key);
    _memory[key] = t;
    while (_memory.length > _memoryKeep) {
      _memory.remove(_memory.keys.first);
    }
  }

  @visibleForTesting
  static int get memoryCount => _memory.length;

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  /// Whether the transcript button should show for [item]. Reactive for
  /// YouTube episodes (read inside an Obx).
  static bool available(MediaItem? item) {
    final src = transcriptSourceFor(item);
    if (src == null) return false;
    if (!src.isYoutube) return true;
    return youtubeAvailable[src.youtubeId] ?? false;
  }

  /// For a YouTube episode, check (once) whether it has captions.
  static Future<void> probe(MediaItem item) async {
    final src = transcriptSourceFor(item);
    if (src == null || !src.isYoutube) return;
    final id = src.youtubeId!;
    if (youtubeAvailable.containsKey(id)) return;
    final cached = _cached(src.key);
    if (cached != null) {
      youtubeAvailable[id] = cached.cues.isNotEmpty;
      return;
    }
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.closedCaptions
          .getManifest(id, formats: const [ClosedCaptionFormat.vtt]);
      youtubeAvailable[id] = manifest.tracks.isNotEmpty;
    } catch (e) {
      printERROR('Caption probe failed ($id): $e');
    } finally {
      yt.close();
    }
  }

  /// The transcript for [item]: memory, then the box, then the network.
  static Future<LoadedTranscript> load(MediaItem item) {
    final src = transcriptSourceFor(item);
    if (src == null) return Future.value(const LoadedTranscript([]));
    final hit = _memory[src.key] ?? _cached(src.key);
    if (hit != null) {
      _remember(src.key, hit);
      return Future.value(hit);
    }
    return _inFlight[src.key] ??= _fetch(src).whenComplete(() {
      _inFlight.remove(src.key);
    });
  }

  static LoadedTranscript? _cached(String key) {
    final raw = _box?.get(key);
    if (!transcriptCacheUsable(raw)) return null;
    final list = raw['cues'];
    return LoadedTranscript(
      [
        if (list is List)
          for (final j in list)
            if (PodcastTranscriptCue.fromJson(j) case final c?) c
      ],
      youtube: raw['yt'] == true,
      auto: raw['auto'] == true,
    );
  }

  static Future<LoadedTranscript> _fetch(TranscriptSource src) async {
    final LoadedTranscript out;
    if (src.isYoutube) {
      out = await _youtube(src.youtubeId!);
      youtubeAvailable[src.youtubeId!] = out.cues.isNotEmpty;
    } else {
      out = LoadedTranscript(
          await PodcastService.transcript(src.url, type: src.type));
    }
    if (out.cues.isNotEmpty) {
      _remember(src.key, out);
      await _save(src.key, out);
    }
    return out;
  }

  static Future<LoadedTranscript> _youtube(String id) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.closedCaptions
          .getManifest(id, formats: const [ClosedCaptionFormat.vtt]);
      final tracks = manifest.tracks.toList();
      final pick = pickCaptionTrack([
        for (final t in tracks)
          (lang: t.language.code, auto: t.isAutoGenerated)
      ], _appLanguage());
      if (pick < 0) return const LoadedTranscript([], youtube: true);
      final track = tracks[pick];
      final vtt = await yt.videos.closedCaptions.getSubTitles(track);
      return LoadedTranscript(
        PodcastService.parseTranscriptDocument(vtt,
            type: 'text/vtt', rolling: track.isAutoGenerated),
        youtube: true,
        auto: track.isAutoGenerated,
      );
    } catch (e) {
      printERROR('YouTube captions failed ($id): $e');
      return const LoadedTranscript([], youtube: true);
    } finally {
      yt.close();
    }
  }

  static String _appLanguage() {
    final l = Get.locale?.languageCode;
    if (l != null && l.isNotEmpty) return l;
    try {
      return Platform.localeName;
    } catch (_) {
      return 'en';
    }
  }

  static Future<void> _save(String key, LoadedTranscript t) async {
    final b = _box;
    if (b == null) return;
    try {
      await b.put(key, {
        'at': DateTime.now().millisecondsSinceEpoch,
        'yt': t.youtube,
        'auto': t.auto,
        'cues': [for (final c in t.cues) c.toJson()],
      });
      final ages = <String, int>{
        for (final k in b.keys)
          if (b.get(k) case {'at': final int at}) '$k': at
      };
      final drop = transcriptKeysToEvict(ages, _keep);
      if (drop.isNotEmpty) await b.deleteAll(drop);
    } catch (e) {
      printERROR('Transcript cache write failed: $e');
    }
  }

  /// Test hook: forget the in-memory copies.
  static void clearMemory() {
    _memory.clear();
    youtubeAvailable.clear();
  }
}
