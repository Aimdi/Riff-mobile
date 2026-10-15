import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:harmonymusic/ui/widgets/total_length.dart';

MediaItem _song(String id, Duration? length) =>
    MediaItem(id: id, title: id, duration: length);

class _Translations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'en_US': {
          'songCount': '@count songs',
          'songCountOne': '1 song',
          'lengthMinutes': '@minutes min',
          'lengthHours': '@hours h',
          'lengthHoursMinutes': '@hours h @minutes min',
        }
      };
}

class _Screen extends GetxController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// An album's or a playlist's length after its count, as Spotify ("12
/// songs, 45 min") and Apple Music give it.
void main() {
  setUp(() {
    Get.addTranslations(_Translations().keys);
    Get.locale = const Locale('en', 'US');
  });
  tearDown(Get.reset);

  test('the songs\' lengths together, when each is known', () {
    expect(
        totalLength([
          _song('a', const Duration(minutes: 3, seconds: 58)),
          _song('b', const Duration(minutes: 4, seconds: 2)),
        ]),
        const Duration(minutes: 8));
    // One unknown: no total (it would come out short).
    expect(
        totalLength([
          _song('a', const Duration(minutes: 3)),
          _song('b', null),
        ]),
        isNull);
    expect(totalLength([_song('a', const Duration(seconds: 40))]), isNull);
    expect(totalLength(const []), isNull);
  });

  test('in whole minutes, with hours from an hour on', () {
    expect(lengthLabel(const Duration(minutes: 52, seconds: 29)), '52 min');
    expect(lengthLabel(const Duration(minutes: 52, seconds: 31)), '53 min');
    expect(lengthLabel(const Duration(hours: 1, minutes: 12)), '1 h 12 min');
    expect(lengthLabel(const Duration(hours: 3)), '3 h');
    expect(lengthLabel(const Duration(minutes: 59, seconds: 50)), '1 h');
  });

  testWidgets('after the count in the list\'s bar', (tester) async {
    Widget bar(Duration? length) => MaterialApp(
          home: Scaffold(
            body: SortWidget(
              tag: 'album-${length?.inSeconds}',
              itemCountTitle: '14',
              itemIcon: Icons.music_note,
              totalLength: length,
              screenController: _Screen(),
              onSort: (_, __) {},
            ),
          ),
        );
    await tester.pumpWidget(bar(const Duration(minutes: 52)));
    expect(find.text('14 songs · 52 min'), findsOneWidget);

    // Not known: the count alone, as before.
    await tester.pumpWidget(bar(null));
    expect(find.text('14 songs'), findsOneWidget);
  });
}
