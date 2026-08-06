/// Scoring for "which YouTube Music result is actually this Spotify track?".
///
/// The import path used to take the first search hit unconditionally, so a
/// remix, a live cut, a sped-up upload or a karaoke version outranked the real
/// recording whenever YouTube happened to return it first. Spotify already
/// gives us the title, the artists and the exact duration; scoring against all
/// three is what turns an imported playlist into the right songs.
///
/// All functions here are pure so they can be tested without a network.
library;

/// Bracketed junk Spotify and YouTube disagree about constantly:
/// "(Remastered 2011)", "[Official Video]", "- Live at Wembley".
final _bracketed = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
final _featuring =
    RegExp(r'\b(feat|ft|featuring|with)\b\.?.*$', caseSensitive: false);
final _trailingDash = RegExp(r'\s-\s.*$');
// Unicode-aware: keep letters and numbers from ANY script. Using [^a-z0-9]
// here would erase CJK and Cyrillic titles entirely and make every such
// comparison score 0.
final _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
// Apostrophes are removed rather than turned into spaces: "don't" and "dont"
// must collapse to the same token, and splitting the word shifts every
// subsequent bigram, which quietly depresses the score for a correct match.
final _apostrophes = RegExp(r"['‘’ʼ]");

/// Lowercased, de-punctuated form used for comparison. Deliberately lossy:
/// the point is that two spellings of the same recording collapse together.
String normalizeForMatch(String raw) {
  var s = raw.toLowerCase();
  s = s.replaceAll(_bracketed, ' ');
  s = s.replaceAll(_trailingDash, ' ');
  s = s.replaceAll(_featuring, ' ');
  s = s.replaceAll(_apostrophes, '');
  s = s.replaceAll(_nonAlnum, ' ');
  return s.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Character bigrams of a normalized string, spaces removed.
Set<String> bigramsOf(String normalized) {
  final s = normalized.replaceAll(' ', '');
  if (s.length < 2) return s.isEmpty ? <String>{} : {s};
  final out = <String>{};
  for (var i = 0; i < s.length - 1; i++) {
    out.add(s.substring(i, i + 2));
  }
  return out;
}

/// Sørensen–Dice coefficient over character bigrams, 0..1.
///
/// Chosen over exact equality because YouTube titles carry extra words far
/// more often than they are simply wrong, and over edit distance because it is
/// cheap and order-insensitive for multi-artist strings.
double diceSimilarity(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  var overlap = 0;
  for (final g in a) {
    if (b.contains(g)) overlap++;
  }
  return (2 * overlap) / (a.length + b.length);
}

double similarityOf(String a, String b) => diceSimilarity(
    bigramsOf(normalizeForMatch(a)), bigramsOf(normalizeForMatch(b)));

/// 1.0 for an exact duration match, decaying to 0 by [toleranceSec].
///
/// Duration is the strongest available signal that two recordings are the same
/// take: a remix or live version almost always differs by more than a few
/// seconds, even when the title does not say so.
double durationScore(int? spotifyMs, Duration? candidate,
    {int toleranceSec = 20}) {
  if (spotifyMs == null || spotifyMs <= 0 || candidate == null) return 0.0;
  final driftSec = ((spotifyMs / 1000) - candidate.inSeconds).abs();
  if (driftSec >= toleranceSec) return 0.0;
  return 1.0 - (driftSec / toleranceSec);
}

/// Weighted 0..1 confidence that [candidateTitle]/[candidateArtist] is the
/// recording described by the Spotify fields.
///
/// When the candidate carries no duration the duration term is dropped and the
/// remaining weights are renormalized, so a result is never punished merely for
/// missing metadata — that would systematically favour whichever source
/// happened to report a length.
double matchScore({
  required String spotifyTitle,
  required String spotifyArtists,
  int? spotifyDurationMs,
  required String candidateTitle,
  String? candidateArtist,
  Duration? candidateDuration,
}) {
  const wTitle = 0.45;
  const wArtist = 0.35;
  const wDuration = 0.20;

  final title = similarityOf(spotifyTitle, candidateTitle);
  final artist = similarityOf(spotifyArtists, candidateArtist ?? '');

  final hasDuration = spotifyDurationMs != null &&
      spotifyDurationMs > 0 &&
      candidateDuration != null;
  if (!hasDuration) {
    return (title * wTitle + artist * wArtist) / (wTitle + wArtist);
  }
  final dur = durationScore(spotifyDurationMs, candidateDuration);
  return title * wTitle + artist * wArtist + dur * wDuration;
}

/// Below this the best candidate is not plausibly the requested recording, and
/// importing it would put a stranger's song in the user's playlist. Kept low on
/// purpose: the goal is to reject the clearly-wrong, not to demand perfection.
const double kMinAcceptableMatch = 0.30;

/// A scored candidate, so callers can rank without re-deriving anything.
class ScoredCandidate<T> {
  const ScoredCandidate(this.item, this.score);
  final T item;
  final double score;
}

/// Best-scoring candidate, or null when the list is empty or nothing clears
/// [kMinAcceptableMatch].
///
/// Ties keep the earlier entry, preserving YouTube Music's own ranking as the
/// tie-break rather than reordering equally-good results arbitrarily.
ScoredCandidate<T>? bestMatch<T>(
  List<T> candidates, {
  required double Function(T) score,
  double minScore = kMinAcceptableMatch,
}) {
  ScoredCandidate<T>? best;
  for (final c in candidates) {
    final s = score(c);
    if (best == null || s > best.score) best = ScoredCandidate<T>(c, s);
  }
  if (best == null || best.score < minScore) return null;
  return best;
}
