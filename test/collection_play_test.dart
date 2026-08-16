import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/collection_play.dart';

void main() {
  test('system library playlist ids', () {
    expect(isSystemLibraryPlaylistId('LIBFAV'), isTrue);
    expect(isSystemLibraryPlaylistId('LIBRP'), isTrue);
    expect(isSystemLibraryPlaylistId('SongsCache'), isTrue);
    expect(isSystemLibraryPlaylistId('SongDownloads'), isTrue);
    expect(isSystemLibraryPlaylistId('PLabc'), isFalse);
  });
}
