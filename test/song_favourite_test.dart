import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/song_favourite.dart';

MediaItem _song(String id) => MediaItem(
      id: id,
      title: 'Song $id',
      extras: const {
        'album': null,
        'artists': [
          {'name': 'Artist', 'id': null}
        ],
        'length': '3:00',
      },
    );

void main() {
  test('liking writes MediaItemBuilder JSON under the song id', () {
    final song = _song('vid1');
    final libFav = <dynamic, dynamic>{};
    final plan = planFavouriteToggle(song, currentlyFavourite: false);
    expect(plan.adding, isTrue);
    expect(plan.songId, 'vid1');
    expect(plan.record, isNotNull);
    expect(plan.record!['videoId'], 'vid1');
    expect(plan.record!['title'], 'Song vid1');

    applyFavouriteToggle(libFav, plan);
    expect(libFav.containsKey('vid1'), isTrue);
    expect(libFav['vid1']['videoId'], 'vid1');
  });

  test('unliking removes the LIBFAV record', () {
    final song = _song('vid1');
    final libFav = <dynamic, dynamic>{
      'vid1': {'videoId': 'vid1'},
    };
    final plan = planFavouriteToggle(song, currentlyFavourite: true);
    expect(plan.adding, isFalse);
    expect(plan.record, isNull);

    applyFavouriteToggle(libFav, plan);
    expect(libFav.containsKey('vid1'), isFalse);
  });

  test('row heart ignores a second tap inside the debounce window', () {
    final first = DateTime(2026, 1, 1, 12, 0, 0);
    expect(shouldIgnoreHeartToggle(null, first), isFalse);
    expect(
      shouldIgnoreHeartToggle(
        first,
        first.add(const Duration(milliseconds: 399)),
      ),
      isTrue,
    );
    expect(
      shouldIgnoreHeartToggle(
        first,
        first.add(const Duration(milliseconds: 400)),
      ),
      isFalse,
    );
  });
}
