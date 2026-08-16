import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/list_widget.dart';
import 'package:harmonymusic/ui/widgets/separate_tab_item_widget.dart';

void main() {
  test('search overview rows play as a queue', () {
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: false, title: 'Songs'),
      isTrue,
    );
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: false, title: 'Videos'),
      isTrue,
    );
  });

  test('complete Songs lists play as a queue', () {
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: true, title: 'Songs'),
      isTrue,
    );
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: true, title: 'library Songs'),
      isTrue,
    );
  });

  test('Play all header shows on Songs/Videos/Episodes tabs', () {
    expect(shouldShowTabPlayAllHeader('Songs'), isTrue);
    expect(shouldShowTabPlayAllHeader('Videos'), isTrue);
    expect(shouldShowTabPlayAllHeader('Episodes'), isTrue);
    expect(shouldShowTabPlayAllHeader('Albums'), isFalse);
    expect(shouldShowTabPlayAllHeader('Artists'), isFalse);
  });

  test('search album/playlist long-press offers play next and radio', () {
    expect(
      wideCollectionLongPressPlayKeys(),
      ['play', 'shuffle', 'playNext', 'startRadio'],
    );
  });

  test('complete Videos and Episodes lists play as a queue', () {
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: true, title: 'Videos'),
      isTrue,
    );
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: true, title: 'Episodes'),
      isTrue,
    );
  });

  test('empty list copy uses existing localization keys', () {
    expect(emptyListLabelKey('Songs'), 'emptyPlaylist');
    expect(emptyListLabelKey('Videos'), 'emptyPlaylist');
    expect(emptyListLabelKey('Episodes'), 'emptyPlaylist');
    expect(emptyListLabelKey('Albums'), 'noBookmarks');
    expect(emptyListLabelKey('Artists'), 'noBookmarks');
  });
}
