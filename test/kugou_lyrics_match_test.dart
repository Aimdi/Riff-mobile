import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/kugou_lyrics_match.dart';

/// Shape of a real krcs.kugou.com/search candidate (durations in ms).
Map<String, dynamic> cand({
  required String id,
  String song = '',
  String singer = '',
  int? durationMs,
  int score = 0,
}) =>
    {
      'id': id,
      'accesskey': 'ak-$id',
      'song': song,
      'singer': singer,
      if (durationMs != null) 'duration': durationMs,
      'score': score,
    };

void main() {
  group('parseKuGouCandidates', () {
    test('reads song/singer/duration/score and skips unusable entries', () {
      final list = parseKuGouCandidates({
        'status': 200,
        'candidates': [
          cand(
              id: 'a',
              song: 'Sunflower',
              singer: 'Post Malone',
              durationMs: 158000,
              score: 60),
          {'id': 'no-key', 'song': 'x'}, // missing accesskey
          'garbage',
        ],
      });
      expect(list, hasLength(1));
      expect(list.single.id, 'a');
      expect(list.single.accessKey, 'ak-a');
      expect(list.single.song, 'Sunflower');
      expect(list.single.singer, 'Post Malone');
      expect(list.single.durationSec, 158);
      expect(list.single.score, 60);
    });

    test('tolerates a missing or malformed candidates array', () {
      expect(parseKuGouCandidates(null), isEmpty);
      expect(parseKuGouCandidates({'status': 404}), isEmpty);
      expect(parseKuGouCandidates({'candidates': 'nope'}), isEmpty);
    });
  });

  group('normalizeKuGouDuration', () {
    test('scales milliseconds to seconds but leaves seconds alone', () {
      expect(normalizeKuGouDuration(251000), 251);
      expect(normalizeKuGouDuration(251), 251);
      expect(normalizeKuGouDuration('251000'), 251);
    });

    test('treats missing or zero durations as unknown', () {
      expect(normalizeKuGouDuration(null), isNull);
      expect(normalizeKuGouDuration(0), isNull);
      expect(normalizeKuGouDuration('abc'), isNull);
    });
  });

  group('pickBestKuGouCandidate', () {
    test('regression: does not take candidates[0] when its duration is off',
        () {
      // The exact defect: a keyword search whose first hit is a different
      // track (a 6-minute remix) with the real 3:31 match further down.
      final cands = parseKuGouCandidates({
        'candidates': [
          cand(
              id: 'remix',
              song: 'Faded (Remix)',
              singer: 'Alan Walker',
              durationMs: 372000,
              score: 90),
          cand(
              id: 'live',
              song: 'Faded (Live)',
              singer: 'Alan Walker',
              durationMs: 245000),
          cand(
              id: 'real',
              song: 'Faded',
              singer: 'Alan Walker',
              durationMs: 212000),
        ],
      });
      final best = pickBestKuGouCandidate(cands,
          targetDurationSec: 212, title: 'Faded', artist: 'Alan Walker');
      expect(best, isNotNull);
      expect(best!.id, 'real');
      expect(best.accessKey, 'ak-real');
    });

    test('picks the closest duration, not merely the first in tolerance', () {
      final cands = parseKuGouCandidates({
        'candidates': [
          cand(id: 'near', song: 'Song', durationMs: 216000),
          cand(id: 'exact', song: 'Song', durationMs: 213000),
        ],
      });
      expect(
        pickBestKuGouCandidate(cands, targetDurationSec: 213)!.id,
        'exact',
      );
    });

    test('keyword search returns null when nothing matches the duration', () {
      final cands = parseKuGouCandidates({
        'candidates': [
          cand(id: 'wrong', song: 'Some Cover', durationMs: 300000, score: 99),
        ],
      });
      expect(
        pickBestKuGouCandidate(cands,
            targetDurationSec: 212, requireDurationMatch: true),
        isNull,
      );
    });

    test('hash search still falls back to the first candidate', () {
      final cands = parseKuGouCandidates({
        'candidates': [
          cand(id: 'first', song: 'Song', durationMs: 300000),
          cand(id: 'second', song: 'Song', durationMs: 301000),
        ],
      });
      expect(
        pickBestKuGouCandidate(cands,
                targetDurationSec: 212, requireDurationMatch: false)!
            .id,
        'first',
      );
    });

    test('falls back when the target duration or candidate durations are'
        ' unknown', () {
      final noDur = parseKuGouCandidates({
        'candidates': [
          cand(id: 'first', song: 'Song'),
          cand(id: 'second', song: 'Song'),
        ],
      });
      expect(pickBestKuGouCandidate(noDur, targetDurationSec: 212)!.id, 'first');

      final withDur = parseKuGouCandidates({
        'candidates': [cand(id: 'only', song: 'Song', durationMs: 300000)],
      });
      expect(pickBestKuGouCandidate(withDur, targetDurationSec: 0)!.id, 'only');

      expect(pickBestKuGouCandidate(const [], targetDurationSec: 212), isNull);
    });

    test('honours the tolerance bound', () {
      final cands = parseKuGouCandidates({
        'candidates': [cand(id: 'a', durationMs: 218000)],
      });
      expect(
          pickBestKuGouCandidate(cands,
              targetDurationSec: 212, toleranceSec: 5),
          isNull);
      expect(
          pickBestKuGouCandidate(cands,
                  targetDurationSec: 212, toleranceSec: 6)!
              .id,
          'a');
    });

    test('breaks duration ties on text, then on KuGou score', () {
      final cands = parseKuGouCandidates({
        'candidates': [
          cand(
              id: 'other',
              song: 'Different Song',
              singer: 'Someone Else',
              durationMs: 212000,
              score: 80),
          cand(
              id: 'match',
              song: 'Faded',
              singer: 'Alan Walker',
              durationMs: 212000,
              score: 10),
        ],
      });
      expect(
        pickBestKuGouCandidate(cands,
                targetDurationSec: 212, title: 'Faded', artist: 'Alan Walker')!
            .id,
        'match',
      );

      final tied = parseKuGouCandidates({
        'candidates': [
          cand(id: 'low', song: 'Faded', durationMs: 212000, score: 10),
          cand(id: 'high', song: 'Faded', durationMs: 212000, score: 90),
        ],
      });
      expect(
        pickBestKuGouCandidate(tied, targetDurationSec: 212, title: 'Faded')!.id,
        'high',
      );
    });

    test('text affinity never overrides a better duration match', () {
      final cands = parseKuGouCandidates({
        'candidates': [
          cand(
              id: 'titled',
              song: 'Faded',
              singer: 'Alan Walker',
              durationMs: 216000),
          cand(id: 'untitled', durationMs: 212000),
        ],
      });
      expect(
        pickBestKuGouCandidate(cands,
                targetDurationSec: 212, title: 'Faded', artist: 'Alan Walker')!
            .id,
        'untitled',
      );
    });
  });

  group('normalizeKuGouText', () {
    test('keeps CJK, which is exactly why KuGou is in the chain', () {
      expect(normalizeKuGouText('稻香 (Live)'), '稻香live');
      expect(normalizeKuGouText('周杰倫 - 稻香'), '周杰倫稻香');
      expect(normalizeKuGouText('ハルジオン'), 'ハルジオン');
    });

    test('drops punctuation and case but keeps modifier words', () {
      expect(normalizeKuGouText('Song (Slowed + Reverb)'), 'songslowedreverb');
      expect(normalizeKuGouText('Sunflower'),
          isNot(normalizeKuGouText('Sunflower (Slowed)')));
    });

    test('CJK titles survive candidate picking end to end', () {
      final cands = parseKuGouCandidates({
        'candidates': [
          cand(id: 'wrong', song: '青花瓷', singer: '周杰倫', durationMs: 239000),
          cand(id: 'right', song: '稻香', singer: '周杰倫', durationMs: 223000),
        ],
      });
      expect(
        pickBestKuGouCandidate(cands,
                targetDurationSec: 223, title: '稻香', artist: '周杰倫')!
            .id,
        'right',
      );
    });
  });
}
