// Pure scoring math for the discovery taste model.
// No Flutter / Hive / GetX imports — unit-testable in isolation.

import 'dart:math' as math;

/// Exponential decay: value halves every [halfLife].
double decayed(double value, Duration elapsed, Duration halfLife) {
  if (value == 0) return 0;
  if (elapsed.isNegative) return value;
  if (halfLife.inMilliseconds <= 0) return value;
  final hlMs = halfLife.inMilliseconds.toDouble();
  final tMs = elapsed.inMilliseconds.toDouble();
  // value * 0.5^(t / halfLife)
  final exponent = tMs / hlMs;
  return value * math.pow(0.5, exponent).toDouble();
}

/// Default half-life for artist affinity (~90 days).
const Duration affinityHalfLife = Duration(days: 90);

/// Half-life for track familiarity (~180 days).
const Duration familiarityHalfLife = Duration(days: 180);

/// Normalize a messy YTM artist string into a stable key.
/// Lowercase, strip "feat. …" / "ft. …", drop punctuation, collapse whitespace.
String normalizeArtistKey(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  var s = raw.toLowerCase().trim();

  // Strip featured artists
  s = s.replaceAll(
      RegExp(r'\s*\(?(?:feat\.?|ft\.?|featuring)\s+[^)]*\)?',
          caseSensitive: false),
      '');
  s = s.replaceAll(RegExp(r'\s+with\s+.*$', caseSensitive: false), '');

  // Drop punctuation; keep Unicode letters/numbers (Željko, Björk, …).
  // Note: Dart `\w` does NOT match Latin Extended even with unicode:true.
  s = s.replaceAll('&', ' ');
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Normalize title for dedupe (remaster twins, re-uploads).
String normalizeTitleKey(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  var s = raw.toLowerCase().trim();
  s = s.replaceAll(
      RegExp(
          r'\s*[\(\[][^\)\]]*(remaster|remix|version|edit|live|deluxe|anniversary|explicit|clean)[^\)\]]*[\)\]]',
          caseSensitive: false),
      '');
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Composite track key for cross-upload dedupe.
String trackDedupeKey(String? title, String? artist) =>
    '${normalizeTitleKey(title)}|${normalizeArtistKey(artist)}';

/// Classify listen quality from fraction listened.
enum ListenQuality { strongPositive, weakPositive, negative }

ListenQuality classifyListen(double fraction) {
  if (fraction >= 0.85) return ListenQuality.strongPositive;
  if (fraction >= 0.30) return ListenQuality.weakPositive;
  return ListenQuality.negative;
}

/// Suggested affinity weight deltas.
class AffinityWeights {
  static const double fullListen = 1.0;
  static const double fullListenUserInitiated = 1.5;
  static const double weakListen = 0.4;
  static const double favorite = 3.0;
  static const double playlistAdd = 2.0;
  static const double download = 2.0;
  static const double follow = 5.0;
  static const double thumbsUp = 2.5;
  static const double skip = -1.0;
  static const double quickSkip = -2.0;
  static const double neverPlay = -4.0;
  static const double thumbsDown = -3.0;
  static const double dismiss = -1.5;
}

/// Greedy re-rank with per-artist caps and no back-to-back same artist.
/// Multi-pass so candidates skipped for adjacency can fill later slots.
List<T> greedyConstrainedPick<T>({
  required List<({double score, String artistKey, T item})> scored,
  required int limit,
  int maxPerArtist = 2,
  int? rollingWindow,
  int maxInRollingWindow = 2,
}) {
  final out = <T>[];
  final used = <int>{};
  final artistCounts = <String, int>{};
  final rolling = <String>[];
  String? lastArtist;

  bool tryPick(int i) {
    if (used.contains(i)) return false;
    final entry = scored[i];
    final key = entry.artistKey;
    if (key.isNotEmpty) {
      if ((artistCounts[key] ?? 0) >= maxPerArtist) return false;
      if (lastArtist != null && lastArtist == key) return false;
      if (rollingWindow != null && rollingWindow > 0) {
        final inWindow = rolling.where((a) => a == key).length;
        if (inWindow >= maxInRollingWindow) return false;
      }
    }
    out.add(entry.item);
    used.add(i);
    if (key.isNotEmpty) {
      artistCounts[key] = (artistCounts[key] ?? 0) + 1;
      lastArtist = key;
      if (rollingWindow != null) {
        rolling.add(key);
        if (rolling.length > rollingWindow) rolling.removeAt(0);
      }
    } else {
      lastArtist = key;
    }
    return true;
  }

  // Keep scanning until full or a full pass adds nothing.
  var progress = true;
  while (out.length < limit && progress) {
    progress = false;
    for (var i = 0; i < scored.length; i++) {
      if (out.length >= limit) break;
      if (tryPick(i)) progress = true;
    }
  }
  return out;
}

/// Deterministic seeded RNG for reproducible tests / mix generation.
class SeededRng {
  int _state;
  SeededRng(int seed) : _state = seed & 0x7fffffff;

  double nextDouble() {
    _state = (1664525 * _state + 1013904223) & 0x7fffffff;
    return _state / 0x80000000;
  }

  int nextInt(int max) {
    if (max <= 0) return 0;
    return (nextDouble() * max).floor();
  }

  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}
