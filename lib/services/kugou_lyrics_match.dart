/// Pure candidate-matching helpers for KuGou's lyric search.
///
/// `krcs.kugou.com/search` answers with a `candidates` list where every entry
/// carries `song`, `singer` and `duration` next to the `id`/`accesskey` pair
/// needed to download the LRC. Taking `candidates[0]` blindly is how a wrong
/// track's lyrics end up cached forever under a song id, so callers walk the
/// list and keep the closest duration match instead.
///
/// Everything in this file is side-effect free so it can be unit tested
/// without touching the network.
library;

class KuGouLyricCandidate {
  const KuGouLyricCandidate({
    required this.id,
    required this.accessKey,
    this.song = '',
    this.singer = '',
    this.durationSec,
    this.score = 0,
  });

  final dynamic id;
  final dynamic accessKey;
  final String song;
  final String singer;

  /// Candidate length in seconds, or null when the response omitted it.
  final int? durationSec;

  /// KuGou's own confidence score for the candidate (0 when absent).
  final int score;
}

/// Parses the `candidates` array of a krcs.kugou.com response.
///
/// Accepts the decoded response map (or the candidate list directly) and
/// silently skips entries that are not usable (missing id/accesskey).
List<KuGouLyricCandidate> parseKuGouCandidates(dynamic data) {
  dynamic raw = data;
  if (raw is Map) raw = raw['candidates'];
  if (raw is! List) return const [];

  final out = <KuGouLyricCandidate>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final accessKey = entry['accesskey'] ?? entry['accessKey'];
    if (id == null || accessKey == null) continue;
    out.add(KuGouLyricCandidate(
      id: id,
      accessKey: accessKey,
      song: _asText(entry['song']),
      singer: _asText(entry['singer']),
      durationSec: normalizeKuGouDuration(entry['duration']),
      score: _asInt(entry['score']) ?? 0,
    ));
  }
  return out;
}

/// Normalises a raw `duration` field to whole seconds.
///
/// The lyric search reports milliseconds while the mobile song search reports
/// seconds, and both flow through here. A value of 10000 or more can only be
/// milliseconds — 10000 seconds is nearly three hours — so it is scaled down.
int? normalizeKuGouDuration(dynamic raw) {
  final n = raw is num ? raw : (raw is String ? num.tryParse(raw) : null);
  if (n == null) return null;
  final v = n.round();
  if (v <= 0) return null;
  return v >= 10000 ? (v / 1000).round() : v;
}

/// Picks the candidate whose duration is closest to [targetDurationSec].
///
/// Only candidates within [toleranceSec] of the target are eligible, matching
/// the tolerance the hash-based path already applies. Ties are broken by text
/// affinity with [title]/[artist] and then by KuGou's own score; text is never
/// a gate, only a preference, so a legitimate match is never thrown away over
/// punctuation or a translated title.
///
/// This never returns null for a non-empty list: when no candidate is a better
/// duration match, KuGou's top result stands, which is exactly the behaviour
/// this function replaced. That matters most on the keyword path, which is
/// only reached after the song search already failed to match on duration —
/// rejecting there a second time would delete the fallback's whole purpose.
///
/// If the target duration is unknown, or the top candidate reports no
/// duration, there is nothing to judge it by and it is returned as-is.
KuGouLyricCandidate? pickBestKuGouCandidate(
  List<KuGouLyricCandidate> candidates, {
  required int targetDurationSec,
  int toleranceSec = 5,
  String? title,
  String? artist,
}) {
  if (candidates.isEmpty) return null;

  // KuGou's own ranking is the only quality signal we have, so it is the
  // default answer. We override it in exactly one case: the top result
  // carries a duration and that duration is demonstrably wrong. Anything
  // looser lets a duration-matching karaoke cover outrank the correct entry
  // whenever the correct entry happens to report no duration — which is the
  // original "wrong lyrics cached forever" defect wearing a different hat.
  final first = candidates.first;
  final firstDur = first.durationSec;
  if (targetDurationSec <= 0 || firstDur == null) return first;
  if ((firstDur - targetDurationSec).abs() <= toleranceSec) return first;

  KuGouLyricCandidate? best;
  var bestDrift = 0;
  var bestAffinity = 0;
  for (final c in candidates) {
    final dur = c.durationSec;
    if (dur == null) continue;
    final drift = (dur - targetDurationSec).abs();
    if (drift > toleranceSec) continue;
    final affinity = kugouTextAffinity(c, title: title, artist: artist);
    if (best == null ||
        drift < bestDrift ||
        (drift == bestDrift &&
            (affinity > bestAffinity ||
                (affinity == bestAffinity && c.score > best.score)))) {
      best = c;
      bestDrift = drift;
      bestAffinity = affinity;
    }
  }
  if (best != null) return best;

  // Nothing better found. Returning the top result is exactly the old
  // behaviour — never worse than before. Returning null here instead would
  // gut the keyword fallback: it is only reached when the song search already
  // failed to match on duration, so requiring a duration match a second time
  // rejects precisely the tracks the fallback exists to rescue.
  return candidates.first;
}

/// A small 0..3 preference score for how well a candidate's text matches the
/// track being looked up. Used only to break duration ties — never as a match
/// gate, because KuGou routinely rewrites titles and credits.
int kugouTextAffinity(
  KuGouLyricCandidate candidate, {
  String? title,
  String? artist,
}) {
  var score = 0;
  if (_textOverlaps(candidate.song, title)) score += 2;
  if (_textOverlaps(candidate.singer, artist)) score += 1;
  return score;
}

bool _textOverlaps(String a, String? b) {
  final x = normalizeKuGouText(a);
  final y = normalizeKuGouText(b ?? '');
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.contains(y) || y.contains(x);
}

/// Lowercases and drops everything that is not a unicode letter or digit.
///
/// Deliberately unicode-aware (`\p{L}\p{N}`, not `[a-z0-9]`) so CJK titles —
/// the whole reason KuGou is in the fallback chain — survive normalisation.
String normalizeKuGouText(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

String _asText(dynamic v) => v is String ? v : (v == null ? '' : '$v');

int? _asInt(dynamic v) {
  if (v is num) return v.round();
  if (v is String) return num.tryParse(v)?.round();
  return null;
}
