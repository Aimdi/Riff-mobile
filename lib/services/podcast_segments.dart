import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'podcast_service.dart' show PodcastChapter;

/// What a podcast segment is about. Names match SponsorBlock's categories.
enum SegmentCategory {
  sponsor('sponsor', Color(0xFFFF5470)),
  selfpromo('selfpromo', Color(0xFFFFC145)),
  interaction('interaction', Color(0xFFE76BFF)),
  intro('intro', Color(0xFF5BD6F0)),
  outro('outro', Color(0xFF6F8BFF)),
  preview('preview', Color(0xFF3FA7A0)),
  filler('filler', Color(0xFFA486FF)),
  musicOfftopic('music_offtopic', Color(0xFFFF8A4C));

  const SegmentCategory(this.apiName, this.color);

  /// SponsorBlock's name for the category.
  final String apiName;

  /// Seek-bar marker colour.
  final Color color;

  /// Localisation key of the category's name.
  String get labelKey => 'segCat_$apiName';

  static SegmentCategory? fromApi(Object? name) {
    for (final c in values) {
      if (c.apiName == name || c.name == name) return c;
    }
    return null;
  }
}

/// What playback does when it reaches a segment.
enum SegmentAction {
  autoSkip,
  pill,
  mute,
  ignore;

  static SegmentAction? fromName(Object? name) {
    for (final a in values) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// When overlapping segments merge, the stronger action wins.
  int get strength => switch (this) {
        autoSkip => 3,
        mute => 2,
        pill => 1,
        ignore => 0,
      };
}

enum SegmentSource { chapters, sponsorblock, manual }

/// One stretch of an episode to skip, mute or point out (times in seconds).
class PodcastSegment {
  const PodcastSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.category,
    required this.source,
    this.action = SegmentAction.ignore,
  });

  final String id;
  final double start;
  final double end;
  final SegmentCategory category;
  final SegmentSource source;

  /// Resolved from the user's settings (see [resolveSegments]).
  final SegmentAction action;

  double get length => end - start;

  bool contains(double sec) => sec >= start && sec < end;

  PodcastSegment withAction(SegmentAction a) => PodcastSegment(
      id: id,
      start: start,
      end: end,
      category: category,
      source: source,
      action: a);

  Map<String, Object> toJson() => {
        'id': id,
        'start': start,
        'end': end,
        'category': category.apiName,
        'source': source.name,
      };

  static PodcastSegment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final start = raw['start'], end = raw['end'];
    final cat = SegmentCategory.fromApi(raw['category']);
    if (start is! num || end is! num || cat == null) return null;
    if (end <= start || start < 0) return null;
    final source = SegmentSource.values
            .firstWhereOrNull((s) => s.name == raw['source']) ??
        SegmentSource.manual;
    return PodcastSegment(
      id: '${raw['id'] ?? '${source.name}_${start}_$end'}',
      start: start.toDouble(),
      end: end.toDouble(),
      category: cat,
      source: source,
    );
  }

  @override
  String toString() =>
      'PodcastSegment($id ${category.apiName} ${start.toStringAsFixed(1)}–${end.toStringAsFixed(1)} ${action.name})';
}

// ---------------------------------------------------------------------------
// Settings: one action per category.

const defaultSegmentActions = <SegmentCategory, SegmentAction>{
  SegmentCategory.sponsor: SegmentAction.autoSkip,
  SegmentCategory.selfpromo: SegmentAction.pill,
  SegmentCategory.interaction: SegmentAction.pill,
  SegmentCategory.intro: SegmentAction.ignore,
  SegmentCategory.outro: SegmentAction.ignore,
  SegmentCategory.preview: SegmentAction.ignore,
  SegmentCategory.filler: SegmentAction.ignore,
  SegmentCategory.musicOfftopic: SegmentAction.ignore,
};

/// Reads the stored per-category actions. Before any were stored, the old
/// "Skip ads" switch decides sponsors: on → skip them, off → only offer
/// the Skip button (what that switch did before).
Map<SegmentCategory, SegmentAction> parseSegmentActions(Object? stored,
    {Object? legacyAutoSkipAds}) {
  final out = Map<SegmentCategory, SegmentAction>.of(defaultSegmentActions);
  if (stored is Map) {
    stored.forEach((k, v) {
      final c = SegmentCategory.fromApi(k);
      final a = SegmentAction.fromName(v);
      if (c != null && a != null) out[c] = a;
    });
  } else if (legacyAutoSkipAds == false) {
    out[SegmentCategory.sponsor] = SegmentAction.pill;
  }
  return out;
}

Map<String, String> segmentActionsToJson(
        Map<SegmentCategory, SegmentAction> actions) =>
    {for (final e in actions.entries) e.key.apiName: e.value.name};

// ---------------------------------------------------------------------------
// Resolving, merging, deciding.

/// Gives every segment its action, drops the ignored ones, merges
/// overlapping (or touching) segments and sorts by start. With
/// [skippingOn] false (the show turned segment skipping off) nothing is
/// skipped or muted automatically; segments are only pointed out.
List<PodcastSegment> resolveSegments(
  Iterable<PodcastSegment> segments,
  Map<SegmentCategory, SegmentAction> actions, {
  bool skippingOn = true,
}) {
  final resolved = <PodcastSegment>[];
  for (final s in segments) {
    var a = actions[s.category] ?? SegmentAction.ignore;
    if (!skippingOn && (a == SegmentAction.autoSkip || a == SegmentAction.mute)) {
      a = SegmentAction.pill;
    }
    if (a == SegmentAction.ignore || s.length < 0.2) continue;
    resolved.add(s.withAction(a));
  }
  return mergeSegments(resolved);
}

/// Merges overlapping segments into one covering both. The merged segment
/// takes the category and action of the stronger one (auto-skip > mute >
/// pill) and the id of the first.
List<PodcastSegment> mergeSegments(List<PodcastSegment> segments) {
  final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
  final out = <PodcastSegment>[];
  for (final s in sorted) {
    if (out.isEmpty || s.start > out.last.end) {
      out.add(s);
      continue;
    }
    final prev = out.removeLast();
    final strong = s.action.strength > prev.action.strength ? s : prev;
    out.add(PodcastSegment(
      id: prev.id,
      start: prev.start,
      end: s.end > prev.end ? s.end : prev.end,
      category: strong.category,
      source: strong.source,
      action: strong.action,
    ));
  }
  return out;
}

/// The segment playing at [sec], if any.
PodcastSegment? segmentAt(List<PodcastSegment> segments, double sec) {
  for (final s in segments) {
    if (s.contains(sec)) return s;
    if (s.start > sec) break;
  }
  return null;
}

/// Most a position tick can advance during normal playback (ticks are
/// ~0.2 s apart; 3× speed and a slow frame still stay well under this).
const segmentEntryWindowSec = 3.0;

/// True when playback ran into [segment] from before its start, i.e. not
/// a seek into the middle of it. Only then is a segment auto-skipped.
bool enteredFromBefore(PodcastSegment segment, double prevSec, double sec) {
  if (!segment.contains(sec)) return false;
  if (prevSec >= segment.start) return false;
  return sec - prevSec <= segmentEntryWindowSec;
}

/// "0:42", "1:05:09".
String formatSegmentLength(double seconds) {
  final total = seconds.round().clamp(0, 1 << 30);
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

// ---------------------------------------------------------------------------
// Sources.

final _introRe = RegExp(r'\b(intro|introduction|opening)\b', caseSensitive: false);
final _outroRe =
    RegExp(r'\b(outro|credits|closing|end card)\b', caseSensitive: false);
final _previewRe = RegExp(r'\b(preview|coming up|recap)\b', caseSensitive: false);
final _promoRe =
    RegExp(r'\b(self[- ]?promo|patreon|merch|support (us|the show))\b', caseSensitive: false);

/// Segments from a show's own chapters: ad chapters become sponsor
/// segments; intro / outro / preview / self-promo chapters get their
/// category (ignored unless the user turns them on).
List<PodcastSegment> segmentsFromChapters(
    List<PodcastChapter> chapters, double durationSec) {
  final out = <PodcastSegment>[];
  final sorted = [...chapters]..sort((a, b) => a.startSec.compareTo(b.startSec));
  for (var i = 0; i < sorted.length; i++) {
    final c = sorted[i];
    final end = c.endSec ??
        (i + 1 < sorted.length ? sorted[i + 1].startSec : durationSec);
    if (end <= c.startSec) continue;
    final SegmentCategory? cat = c.isAd
        ? SegmentCategory.sponsor
        : _promoRe.hasMatch(c.title)
            ? SegmentCategory.selfpromo
            : _introRe.hasMatch(c.title)
                ? SegmentCategory.intro
                : _outroRe.hasMatch(c.title)
                    ? SegmentCategory.outro
                    : _previewRe.hasMatch(c.title)
                        ? SegmentCategory.preview
                        : null;
    if (cat == null) continue;
    out.add(PodcastSegment(
      id: 'ch_${c.startSec.toStringAsFixed(2)}',
      start: c.startSec,
      end: end,
      category: cat,
      source: SegmentSource.chapters,
    ));
  }
  return out;
}

/// SponsorBlock's privacy-preserving lookup: the first four hex digits of
/// sha256(videoId); the server answers for every video sharing them.
String sponsorBlockHashPrefix(String videoId) =>
    sha256.convert(utf8.encode(videoId)).toString().substring(0, 4);

/// Segments for [videoId] from a `/api/skipSegments/{prefix}` response
/// (a list of `{videoID, segments: [...]}`), other videos dropped.
List<PodcastSegment> parseSponsorBlockHashResponse(
    Object? data, String videoId) {
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return const [];
    }
  }
  if (data is! List) return const [];
  final out = <PodcastSegment>[];
  for (final video in data) {
    if (video is! Map || video['videoID'] != videoId) continue;
    final segs = video['segments'];
    if (segs is! List) continue;
    for (final s in segs) {
      if (s is! Map) continue;
      final range = s['segment'];
      final action = s['actionType'];
      if (action != null && action != 'skip' && action != 'mute') continue;
      if (range is! List || range.length < 2) continue;
      final a = range[0], b = range[1];
      if (a is! num || b is! num || b <= a) continue;
      final cat = SegmentCategory.fromApi(s['category']);
      if (cat == null) continue;
      out.add(PodcastSegment(
        id: 'sb_${s['UUID'] ?? '${a}_$b'}',
        start: a.toDouble(),
        end: b.toDouble(),
        category: cat,
        source: SegmentSource.sponsorblock,
      ));
    }
  }
  out.sort((x, y) => x.start.compareTo(y.start));
  return out;
}

/// SponsorBlock results are kept a day per episode.
const segmentCacheTtl = Duration(hours: 24);

bool segmentCacheFresh(Object? fetchedAtMs, DateTime now) =>
    fetchedAtMs is int &&
    now.millisecondsSinceEpoch - fetchedAtMs < segmentCacheTtl.inMilliseconds &&
    now.millisecondsSinceEpoch >= fetchedAtMs;

/// YouTube video ids are 11 characters of [A-Za-z0-9_-]; RSS episode
/// ids (`podcast_…`) never are, whatever their length.
bool looksLikeYoutubeVideoId(String id) =>
    !id.startsWith('podcast_') && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);

// ---------------------------------------------------------------------------
// Storage.

/// Podcast segment settings, the SponsorBlock cache, manual segments and
/// the time-saved counter. Reads tolerate boxes that aren't open yet.
class PodcastSegmentStore {
  PodcastSegmentStore._();

  static const actionsKey = 'podcastSegmentActions';
  static const cacheBox = 'PodcastSegmentCache';
  static const manualBox = 'PodcastManualSegments';
  static const statsBox = 'PodcastStats';
  static const savedKey = 'segmentSavedMs';

  static final rev = 0.obs;

  static Box? _box(String name) => Hive.isBoxOpen(name) ? Hive.box(name) : null;

  static Map<SegmentCategory, SegmentAction> get actions {
    final p = _box('AppPrefs');
    return parseSegmentActions(p?.get(actionsKey),
        legacyAutoSkipAds: p?.get('podcastAutoSkipAds'));
  }

  static Future<void> setAction(SegmentCategory c, SegmentAction a) async {
    final p = _box('AppPrefs');
    if (p == null) return;
    final next = {...actions, c: a};
    await p.put(actionsKey, segmentActionsToJson(next));
    rev.value++;
  }

  /// Cached SponsorBlock segments for an episode, if still fresh.
  static List<PodcastSegment>? cached(String episodeId, DateTime now) {
    final raw = _box(cacheBox)?.get(episodeId);
    if (raw is! Map || !segmentCacheFresh(raw['fetchedAt'], now)) return null;
    final list = raw['segments'];
    if (list is! List) return null;
    return [
      for (final s in list)
        if (PodcastSegment.fromJson(s) case final seg?) seg
    ];
  }

  static Future<void> putCache(
      String episodeId, List<PodcastSegment> segments, DateTime now) async {
    final box = _box(cacheBox) ?? await Hive.openBox(cacheBox);
    await box.put(episodeId, {
      'fetchedAt': now.millisecondsSinceEpoch,
      'segments': [for (final s in segments) s.toJson()],
    });
  }

  static List<PodcastSegment> manual(String episodeId) {
    final raw = _box(manualBox)?.get(episodeId);
    if (raw is! List) return const [];
    return [
      for (final s in raw)
        if (PodcastSegment.fromJson(s) case final seg?) seg
    ];
  }

  static Future<void> addManual(String episodeId, PodcastSegment s) async {
    final box = _box(manualBox) ?? await Hive.openBox(manualBox);
    final list = [...manual(episodeId), s];
    await box.put(episodeId, [for (final x in list) x.toJson()]);
    rev.value++;
  }

  static Future<void> removeManual(String episodeId, String segmentId) async {
    final box = _box(manualBox);
    if (box == null) return;
    final list = manual(episodeId).where((s) => s.id != segmentId).toList();
    await box.put(episodeId, [for (final x in list) x.toJson()]);
    rev.value++;
  }

  /// Total listening time saved by skipped segments.
  static Duration get timeSaved {
    final v = _box(statsBox)?.get(savedKey);
    return Duration(milliseconds: v is int ? v : 0);
  }

  /// Adds (or, for an undone skip, takes back) saved time; never below 0.
  static Future<void> addTimeSaved(Duration d) async {
    if (d == Duration.zero) return;
    final box = _box(statsBox) ?? await Hive.openBox(statsBox);
    final v = box.get(savedKey);
    final next = (v is int ? v : 0) + d.inMilliseconds;
    await box.put(savedKey, next < 0 ? 0 : next);
  }
}
