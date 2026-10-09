import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';

void main() {
  test('preserves discoveryReason and dailyMix identity through extras', () {
    final item = MediaItemBuilder.fromJson({
      'videoId': 'abc',
      'title': 'Song',
      'artists': [
        {'name': 'Artist', 'id': null}
      ],
      'thumbnails': [
        {'url': 'https://example.com/a.jpg'}
      ],
      'discoveryReason': 'Because you like jazz',
      'dailyMixId': 'mix1',
      'dailyMixTitle': 'Daily Mix 1',
      'discoverySource': 'search',
    });
    expect(item.extras?['discoveryReason'], 'Because you like jazz');
    expect(item.extras?['dailyMixId'], 'mix1');
    expect(item.extras?['dailyMixTitle'], 'Daily Mix 1');
    expect(item.extras?['discoverySource'], 'search');

    final json = MediaItemBuilder.toJson(item);
    expect(json['discoveryReason'], 'Because you like jazz');
    expect(json['dailyMixId'], 'mix1');
    expect(json['discoverySource'], 'search');
  });

  test('parses relative podcast dates into pubDateMs', () {
    final item = MediaItemBuilder.fromJson({
      'videoId': 'ep1',
      'title': 'Episode',
      'date': '2h ago',
      'videoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
      'thumbnails': [
        {'url': 'https://example.com/a.jpg'}
      ],
    });
    final ms = item.extras?['pubDateMs'] as int?;
    expect(ms, isNotNull);
    expect(ms! > 0, isTrue);
    final age = DateTime.now().toUtc().millisecondsSinceEpoch - ms;
    expect(age, lessThan(3 * 60 * 60 * 1000));
    expect(age, greaterThan(60 * 60 * 1000));
  });

  test('a malformed stored length is no duration, not an exception', () {
    expect(MediaItemBuilder.toDuration('3:45'),
        const Duration(minutes: 3, seconds: 45));
    expect(MediaItemBuilder.toDuration('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(MediaItemBuilder.toDuration('Live'), Duration.zero);
    expect(MediaItemBuilder.toDuration('1:xx'), isNull);
    // fromJson is how every library / playlist box is read back.
    final item = MediaItemBuilder.fromJson(
        {'videoId': 'v', 'title': 'T', 'length': '4:0a'});
    expect(item.duration, isNull);
  });
}
