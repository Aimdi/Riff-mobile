import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/soul_sync_service.dart';

void main() {
  test('SoulSyncTrack builds request query from artist and title', () {
    final t = SoulSyncTrack.fromJson({
      'id': '1',
      'name': 'Karma Police',
      'artists': ['Radiohead'],
      'album': 'OK Computer',
      'source': 'spotify',
    });
    expect(t.requestQuery, 'Radiohead - Karma Police');
    expect(t.artistLabel, 'Radiohead');
  });

  test('SoulSyncTrack falls back to title when artists missing', () {
    final t = SoulSyncTrack.fromJson({'id': '2', 'name': 'Untitled'});
    expect(t.requestQuery, 'Untitled');
  });
}
