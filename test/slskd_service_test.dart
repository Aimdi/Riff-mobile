import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/slskd_service.dart';

void main() {
  test('SoulseekHit displayName uses basename', () {
    const hit = SoulseekHit(
      username: 'alice',
      filename: r'@@music\Artist\Album\Track 01.flac',
      size: 12 * 1000 * 1000,
      uploadSpeed: 100,
      queueLength: 0,
      bitRate: 320,
      lengthSeconds: 215,
      extension: 'flac',
    );
    expect(hit.displayName, 'Track 01.flac');
    expect(hit.sizeLabel, contains('MB'));
    expect(hit.metaLabel, contains('alice'));
    expect(hit.metaLabel, contains('320kbps'));
  });

  test('SoulseekHit handles unix-style paths', () {
    const hit = SoulseekHit(
      username: 'bob',
      filename: '/shares/music/song.mp3',
      size: 5000,
      uploadSpeed: 0,
      queueLength: 2,
    );
    expect(hit.displayName, 'song.mp3');
  });
}
