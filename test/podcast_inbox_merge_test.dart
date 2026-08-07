import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors inbox chronological merge used by PodcastInboxScreen.
List<MediaItem> mergeNewestFirst(List<List<MediaItem>> lists) {
  final all = <MediaItem>[for (final l in lists) ...l];
  all.sort((a, b) {
    final am = (a.extras?['pubDateMs'] as int?) ?? 0;
    final bm = (b.extras?['pubDateMs'] as int?) ?? 0;
    if (am == 0 && bm == 0) {
      return (b.extras?['date'] ?? '')
          .toString()
          .compareTo((a.extras?['date'] ?? '').toString());
    }
    if (am == 0) return 1;
    if (bm == 0) return -1;
    return bm.compareTo(am);
  });
  return all;
}

MediaItem _ep(String id, {int pubDateMs = 0, String date = ''}) => MediaItem(
      id: id,
      title: id,
      extras: {'pubDateMs': pubDateMs, 'date': date, 'isPodcast': true},
    );

void main() {
  test('inbox merge sorts by pubDateMs newest first', () {
    final merged = mergeNewestFirst([
      [_ep('a', pubDateMs: 100), _ep('b', pubDateMs: 300)],
      [_ep('c', pubDateMs: 200)],
    ]);
    expect(merged.map((e) => e.id).toList(), ['b', 'c', 'a']);
  });

  test('undated items sort after dated ones', () {
    final merged = mergeNewestFirst([
      [_ep('old', pubDateMs: 0, date: 'yesterday')],
      [_ep('new', pubDateMs: 500)],
    ]);
    expect(merged.first.id, 'new');
    expect(merged.last.id, 'old');
  });
}
