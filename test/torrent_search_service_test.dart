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

  test('TorrentHit prefers detailsUrl when auth download is required', () {
    const hit = TorrentHit(
      name: 'Album',
      infoHash: '',
      magnet: '',
      sizeLabel: '1 MB',
      dateLabel: '2024-01-01',
      seeders: 1,
      leechers: 0,
      downloads: 0,
      source: TorrentSourceId.redacted,
      downloadUrl: 'https://redacted.sh/ajax.php?action=download&id=1',
      detailsUrl: 'https://redacted.sh/torrents.php?id=9&torrentid=1',
      needsAuthDownload: true,
    );
    expect(hit.openUrl, contains('torrents.php'));
    expect(hit.openUrl, isNot(contains('action=download')));
  });

  test('TorrentHit copyWith updates magnet', () {
    const hit = TorrentHit(
      name: 'Song',
      infoHash: '',
      magnet: '',
      sizeLabel: '—',
      dateLabel: '—',
      seeders: 0,
      leechers: 0,
      downloads: 0,
      source: TorrentSourceId.x1337,
      detailsUrl: 'https://1337x.to/torrent/1/x/',
    );
    final resolved = hit.copyWith(magnet: 'magnet:?xt=urn:btih:deadbeef');
    expect(resolved.hasMagnet, isTrue);
    expect(resolved.detailsUrl, hit.detailsUrl);
  });

  test('TorrentSourceId prefs round-trip for all sources', () {
    for (final id in TorrentSourceId.values) {
      expect(TorrentSourceIdX.fromPrefs(id.prefsKey), id);
    }
    expect(TorrentSourceIdX.fromPrefs('unknown'), isNull);
    expect(TorrentSourceId.x1337.prefsKey, '1337x');
    expect(TorrentSourceId.audioBookBay.prefsKey, 'audiobookbay');
  });
}
