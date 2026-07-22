import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/torrents_digger_service.dart';

void main() {
  test('TorrentHit magnet uses info hash and encoded name', () {
    const hit = TorrentHit(
      name: 'Ubuntu 24.04',
      infoHash: 'ABCDEF',
      magnet: 'magnet:?xt=urn:btih:ABCDEF&dn=Ubuntu%2024.04',
      sizeLabel: '1.00 GB',
      dateLabel: '2024-01-01',
      seeders: 10,
      leechers: 1,
      downloads: 100,
    );
    expect(hit.magnet, contains('btih:ABCDEF'));
    expect(hit.name, 'Ubuntu 24.04');
  });
}
