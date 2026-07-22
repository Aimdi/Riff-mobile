import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/torrent_search_service.dart';

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
      source: TorrentSourceId.torrentsCsv,
    );
    expect(hit.magnet, contains('btih:ABCDEF'));
    expect(hit.name, 'Ubuntu 24.04');
    expect(hit.hasMagnet, isTrue);
    expect(hit.openUrl, startsWith('magnet:'));
  });

  test('TorrentHit prefers magnet over downloadUrl for openUrl', () {
    const hit = TorrentHit(
      name: 'Book',
      infoHash: 'abc',
      magnet: 'magnet:?xt=urn:btih:abc',
      sizeLabel: '1 MB',
      dateLabel: '2024-01-01',
      seeders: 1,
      leechers: 0,
      downloads: 0,
      source: TorrentSourceId.myAnonamouse,
      downloadUrl: 'https://www.myanonamouse.net/tor/download.php/x',
    );
    expect(hit.openUrl, startsWith('magnet:'));
  });

  test('TorrentHit falls back to downloadUrl when no magnet', () {
    const hit = TorrentHit(
      name: 'Book',
      infoHash: '',
      magnet: '',
      sizeLabel: '1 MB',
      dateLabel: '2024-01-01',
      seeders: 1,
      leechers: 0,
      downloads: 0,
      source: TorrentSourceId.myAnonamouse,
      downloadUrl: 'https://www.myanonamouse.net/tor/download.php/x',
    );
    expect(hit.hasMagnet, isFalse);
    expect(hit.openUrl, contains('myanonamouse.net'));
  });

  test('TorrentSourceId prefs round-trip', () {
    expect(TorrentSourceId.torrentsCsv.prefsKey, 'torrents_csv');
    expect(TorrentSourceId.myAnonamouse.prefsKey, 'myanonamouse');
    expect(TorrentSourceIdX.fromPrefs('torrents_csv'),
        TorrentSourceId.torrentsCsv);
    expect(TorrentSourceIdX.fromPrefs('myanonamouse'),
        TorrentSourceId.myAnonamouse);
    expect(TorrentSourceIdX.fromPrefs('unknown'), isNull);
  });
}
