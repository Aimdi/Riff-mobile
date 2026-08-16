import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/list_widget.dart';

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

  test('complete non-Songs lists keep radio/single-tap path', () {
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: true, title: 'Videos'),
      isFalse,
    );
    expect(
      shouldPlaySearchRowsAsQueue(isCompleteList: true, title: 'Episodes'),
      isFalse,
    );
  });
}
