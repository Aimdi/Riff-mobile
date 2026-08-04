import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:harmonymusic/utils/hive_safe_open.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hive_safe_open');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    try {
      await Hive.close();
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('safeOpenBox opens a normal box', () async {
    final box = await safeOpenBox('okBox');
    await box.put('a', 1);
    expect(box.get('a'), 1);
    await box.close();
  });

  test('safeOpenBox recovers after deleteBoxFromDisk', () async {
    final box = await safeOpenBox('recoverBox');
    await box.put('x', 'y');
    await box.close();
    await Hive.deleteBoxFromDisk('recoverBox');
    final reopened = await safeOpenBox('recoverBox');
    expect(reopened.get('x'), isNull);
    await reopened.close();
  });
}
