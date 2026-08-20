import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/discovery/discovery_tag.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';

MediaItem _song({String? source}) => MediaItem(
      id: 'vid',
      title: 'Song',
      extras: {
        if (source != null) kDiscoverySourceExtra: source,
      },
    );

void main() {
  test('wire names round-trip for every source', () {
    for (final src in DiscoverySource.values) {
      expect(DiscoverySource.fromWire(src.wireName), src);
    }
  });

  test('sourceFromPlaylingFrom maps album playlist artist', () {
    expect(
      sourceFromPlaylingFrom(PlaylingFrom(type: PlaylingFromType.ALBUM)),
      DiscoverySource.album,
    );
    expect(
      sourceFromPlaylingFrom(PlaylingFrom(type: PlaylingFromType.PLAYLIST)),
      DiscoverySource.playlist,
    );
    expect(
      sourceFromPlaylingFrom(PlaylingFrom(type: PlaylingFromType.ARTIST)),
      DiscoverySource.artist,
    );
    expect(
      sourceFromPlaylingFrom(PlaylingFrom(type: PlaylingFromType.SELECTION)),
      DiscoverySource.userClick,
    );
    expect(sourceFromPlaylingFrom(null), DiscoverySource.userClick);
  });

  test('sourceFromPlaylistId distinguishes system boxes and mixes', () {
    expect(sourceFromPlaylistId('SongDownloads'), DiscoverySource.downloads);
    expect(sourceFromPlaylistId('SongsCache'), DiscoverySource.downloads);
    expect(sourceFromPlaylistId('LIBFAV'), DiscoverySource.downloads);
    expect(sourceFromPlaylistId('LIBRP'), DiscoverySource.home);
    expect(sourceFromPlaylistId('RIFF_daily_1'), DiscoverySource.dailyMix);
    expect(sourceFromPlaylistId('PLabc'), DiscoverySource.playlist);
  });

  test('ensureDiscoverySource does not overwrite an existing tag', () {
    final tagged = ensureDiscoverySource(
      _song(source: 'search'),
      DiscoverySource.userClick,
    );
    expect(sourceFromMediaItem(tagged), DiscoverySource.search);

    final fresh = ensureDiscoverySource(_song(), DiscoverySource.podcast);
    expect(sourceFromMediaItem(fresh), DiscoverySource.podcast);
  });

  test('user-initiated sources include search album and library taps', () {
    expect(DiscoverySource.search.isUserInitiated, isTrue);
    expect(DiscoverySource.album.isUserInitiated, isTrue);
    expect(DiscoverySource.radio.isUserInitiated, isFalse);
    expect(DiscoverySource.freshFinds.isUserInitiated, isFalse);
  });
}
