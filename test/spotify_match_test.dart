import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify_match.dart';

/// A stand-in for the YouTube Music side of a match.
class _Cand {
  const _Cand(this.title, this.artist, this.duration);
  final String title;
  final String? artist;
  final Duration? duration;
}

double _score(_Cand c,
        {required String title, required String artists, int? durationMs}) =>
    matchScore(
      spotifyTitle: title,
      spotifyArtists: artists,
      spotifyDurationMs: durationMs,
      candidateTitle: c.title,
      candidateArtist: c.artist,
      candidateDuration: c.duration,
    );

void main() {
  group('normalizeForMatch', () {
    test('strips bracketed noise, trailing dash clauses and featuring credits',
        () {
      expect(normalizeForMatch('Song (Remastered 2011)'), 'song');
      expect(normalizeForMatch('Song [Official Video]'), 'song');
      expect(normalizeForMatch('Song - Live at Wembley'), 'song');
      expect(normalizeForMatch('Song feat. Someone'), 'song');
    });

    test('is case and punctuation insensitive', () {
      expect(normalizeForMatch("Don't Stop Me Now!"),
          normalizeForMatch('dont stop me now'));
    });

    // A [^a-z0-9] strip would erase these entirely and score every
    // comparison 0, silently breaking import for non-Latin catalogues.
    test('preserves non-Latin scripts', () {
      expect(normalizeForMatch('稻香 (Live)'), '稻香');
      expect(normalizeForMatch('Кино — Группа крови'), isNotEmpty);
      expect(normalizeForMatch('ハルジオン'), 'ハルジオン');
    });
  });

  group('durationScore', () {
    test('peaks at an exact match and decays to zero at the tolerance', () {
      expect(durationScore(200000, const Duration(seconds: 200)), 1.0);
      expect(durationScore(200000, const Duration(seconds: 220)), 0.0);
      expect(durationScore(200000, const Duration(seconds: 210)),
          closeTo(0.5, 0.01));
    });

    test('is zero when either side is unknown', () {
      expect(durationScore(null, const Duration(seconds: 200)), 0.0);
      expect(durationScore(200000, null), 0.0);
    });
  });

  group('matchScore', () {
    const title = 'Bohemian Rhapsody';
    const artist = 'Queen';
    const durMs = 354000;

    test('the real recording outranks a same-title remix', () {
      const real = _Cand('Bohemian Rhapsody', 'Queen', Duration(seconds: 354));
      const remix = _Cand('Bohemian Rhapsody (Slowed + Reverb)',
          'Some Uploader', Duration(seconds: 421));
      expect(
        _score(real, title: title, artists: artist, durationMs: durMs),
        greaterThan(
            _score(remix, title: title, artists: artist, durationMs: durMs)),
      );
    });

    // The exact failure the old take-the-first-result code produced.
    test('a live version loses to the studio take on duration', () {
      const studio =
          _Cand('Bohemian Rhapsody', 'Queen', Duration(seconds: 354));
      const live = _Cand(
          'Bohemian Rhapsody - Live Aid', 'Queen', Duration(seconds: 264));
      expect(
        _score(studio, title: title, artists: artist, durationMs: durMs),
        greaterThan(
            _score(live, title: title, artists: artist, durationMs: durMs)),
      );
    });

    test('an unrelated song scores below the acceptance floor', () {
      const wrong = _Cand(
          'Never Gonna Give You Up', 'Rick Astley', Duration(seconds: 213));
      expect(_score(wrong, title: title, artists: artist, durationMs: durMs),
          lessThan(kMinAcceptableMatch));
    });

    // Renormalisation guard: a candidate missing duration must not be
    // penalised into oblivion, or results from sources that omit length
    // would always lose to ones that report it.
    test('a candidate without duration is judged on title and artist alone',
        () {
      const noDur = _Cand('Bohemian Rhapsody', 'Queen', null);
      final score =
          _score(noDur, title: title, artists: artist, durationMs: durMs);
      expect(score, greaterThan(0.9),
          reason: 'perfect title+artist should still score near 1.0');
    });
  });

  group('bestMatch', () {
    test('returns null for an empty candidate list', () {
      expect(bestMatch<int>(const [], score: (_) => 1.0), isNull);
    });

    test('rejects everything when the best candidate is clearly wrong', () {
      expect(bestMatch<int>(const [1, 2], score: (_) => 0.05), isNull);
    });

    test('keeps YouTube ranking as the tie-break', () {
      final r = bestMatch<String>(const ['first', 'second'], score: (_) => 0.9);
      expect(r!.item, 'first');
    });

    test('picks the highest scorer, not the first', () {
      final r = bestMatch<String>(
        const ['a', 'b', 'c'],
        score: (s) => s == 'b' ? 0.9 : 0.4,
      );
      expect(r!.item, 'b');
    });
  });
}
