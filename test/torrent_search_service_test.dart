import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/torrent_search_service.dart';

void main() {
  test('rejects queries shorter than 3 characters', () async {
    final service = TorrentSearchService(dio: Dio());
    expect(
      () => service.search('hu'),
      throwsA(
        isA<TorrentSearchException>().having((e) => e.tooShort, 'tooShort', true),
      ),
    );
  });

  test('TorrentHit magnet includes info hash and trackers', () {
    const hit = TorrentHit(
      name: 'Ubuntu 24.04',
      infoHash: 'ABCDEF',
      magnet:
          'magnet:?xt=urn:btih:ABCDEF&dn=Ubuntu%2024.04&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce',
      sizeLabel: '1.00 GB',
      dateLabel: '2024-01-01',
      seeders: 10,
      leechers: 1,
      downloads: 100,
    );
    expect(hit.magnet, contains('btih:ABCDEF'));
    expect(hit.magnet, contains('tr='));
    expect(hit.name, 'Ubuntu 24.04');
  });

  test('live search returns results for a normal query', () async {
    final service = TorrentSearchService();
    final res = await service.search('ubuntu', size: 5);
    expect(res.torrents, isNotEmpty);
    expect(res.torrents.first.infoHash, isNotEmpty);
    expect(res.torrents.first.magnet, startsWith('magnet:?xt=urn:btih:'));
    expect(res.torrents.first.magnet, contains('tr='));
  }, tags: ['network']);
}
