import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/collection_play.dart';

void main() {
  test('collection cards play on the body tap', () {
    expect(shouldPlayCollectionOnTap(), isTrue);
  });

  test('system library playlist ids', () {
    expect(isSystemLibraryPlaylistId('LIBFAV'), isTrue);
    expect(isSystemLibraryPlaylistId('LIBRP'), isTrue);
    expect(isSystemLibraryPlaylistId('SongsCache'), isTrue);
    expect(isSystemLibraryPlaylistId('SongDownloads'), isTrue);
    expect(isSystemLibraryPlaylistId('PLabc'), isFalse);
  });

  test('artistTopSongsFromResponse reads Top songs then Songs', () {
    const song = MediaItem(id: 'a', title: 'A');
    expect(
      artistTopSongsFromResponse({
        'Top songs': {
          'content': [song]
        }
      }).map((e) => e.id),
      ['a'],
    );
    expect(
      artistTopSongsFromResponse({
        'Songs': [song]
      }).map((e) => e.id),
      ['a'],
    );
    expect(artistTopSongsFromResponse(const {}), isEmpty);
  });
}
