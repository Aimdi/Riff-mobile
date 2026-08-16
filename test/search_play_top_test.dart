import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Search/search_play_top.dart';

void main() {
  test('songsFromSearchResult reads the Songs bucket', () {
    const song = MediaItem(id: 'a', title: 'A');
    expect(
      songsFromSearchResult({
        'Songs': [song]
      }).map((e) => e.id),
      ['a'],
    );
    expect(songsFromSearchResult(const {}), isEmpty);
    expect(
      songsFromSearchResult({
        'Songs': ['not-a-song']
      }),
      isEmpty,
    );
  });

  test('search submit plays typed queries, not pasted URLs', () {
    expect(shouldPlaySearchSubmit(''), isFalse);
    expect(shouldPlaySearchSubmit('   '), isFalse);
    expect(shouldPlaySearchSubmit('https://youtube.com/watch?v=x'), isFalse);
    expect(shouldPlaySearchSubmit('radiohead'), isTrue);
  });

  test('suggestion rows play on tap, same as Enter', () {
    expect(shouldPlaySearchItemOnTap(), isTrue);
  });

  test('search play-fail does not blame the network', () {
    expect(searchPlayFailedMessageKey(), 'searchPlayFailed');
    expect(searchPlayFailedMessageKey(), isNot('networkError'));
  });

  test('failed play is reported so the user is not left in silence', () {
    expect(shouldNotifySearchPlayFailed(played: true), isFalse);
    expect(shouldNotifySearchPlayFailed(played: false), isTrue);
  });

  test('submit opens results and reports failure when nothing plays', () async {
    var opened = '';
    var failed = false;
    final ok = await submitSearchQuery(
      'radiohead',
      onLink: (_) {},
      onOpenResults: (q) => opened = q,
      onRemember: (_) {},
      onPlayFailed: () => failed = true,
    );
    expect(ok, isFalse);
    expect(opened, 'radiohead');
    expect(failed, isTrue);
  });
}
