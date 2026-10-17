import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/smart_downloads.dart';
import 'package:harmonymusic/services/song_downloads_removal.dart';
import 'package:harmonymusic/ui/screens/Settings/components/remove_downloads.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _Settings extends GetxController implements SettingsScreenController {
  @override
  final downloadsBytes = (3 * 1024 * 1024).obs;
  int removals = 0;

  @override
  Future<int?> removeAllDownloads() async {
    removals++;
    return 2;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  late Box downloads;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_downloads_');
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    downloads = await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    SmartDownloads.reload();
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  File file(String path) => File('${tmp.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  test(
      'every downloaded song goes, file and cover, and Smart downloads '
      'start afresh', () async {
    final a = file('music/a.m4a');
    final b = file('music/b.opus');
    final coverA = file('thumbnails/aaaaaaaaaaa.png');
    final other = file('music/keep.txt');
    await downloads.putAll({
      'aaaaaaaaaaa': {'videoId': 'aaaaaaaaaaa', 'url': a.path},
      'bbbbbbbbbbb': {'videoId': 'bbbbbbbbbbb', 'url': 'file://${b.path}'},
    });
    await Hive.box('AppPrefs').putAll({
      SmartDownloads.keptKey: ['aaaaaaaaaaa'],
      SmartDownloads.pendingKey: ['ccccccccccc'],
      SmartDownloads.declinedKey: ['ddddddddddd'],
      SmartDownloads.key: true,
    });

    final removed = await removeAllSongDownloads(supportDir: tmp.path);
    expect(removed, unorderedEquals(['aaaaaaaaaaa', 'bbbbbbbbbbb']));
    expect(downloads.isEmpty, isTrue);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
    expect(coverA.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
    final prefs = Hive.box('AppPrefs');
    expect(prefs.get(SmartDownloads.keptKey), isNull);
    expect(prefs.get(SmartDownloads.pendingKey), isNull);
    expect(prefs.get(SmartDownloads.declinedKey), isNull);
    // Still on.
    expect(prefs.get(SmartDownloads.key), isTrue);
  });

  test('nothing downloaded: nothing to do', () async {
    expect(await removeAllSongDownloads(supportDir: tmp.path), isEmpty);
  });

  Future<_Settings> pumpAsk(WidgetTester tester) async {
    final settings =
        Get.put<SettingsScreenController>(_Settings()) as _Settings;
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => removeAllDownloadsAsked(context),
            child: const Text('ask'),
          ),
        ),
      ),
    ));
    return settings;
  }

  testWidgets('asks first, and says what Smart downloads will do',
      (tester) async {
    await tester.runAsync(() async {
      await downloads.putAll({
        'a': {'videoId': 'a'},
        'b': {'videoId': 'b'},
      });
      await Hive.box('AppPrefs').put(SmartDownloads.key, true);
    });
    SmartDownloads.reload();
    final settings = await pumpAsk(tester);
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    expect(find.text('removeAllDownloadsQ'), findsOneWidget);
    expect(find.text('removeAllDownloadsMsg\n\nsmartDownloadsRefill'),
        findsOneWidget);

    // Cancel: nothing removed.
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(settings.removals, 0);

    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('remove'));
    await tester.pumpAndSettle();
    expect(settings.removals, 1);
    expect(find.text('downloadsRemoved'), findsOneWidget);
  });

  testWidgets('with nothing downloaded it asks nothing', (tester) async {
    final settings = await pumpAsk(tester);
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    expect(find.text('removeAllDownloadsQ'), findsNothing);
    expect(settings.removals, 0);
  });
}
