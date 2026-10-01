import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/diag_log.dart';

void main() {
  late Directory dir;

  setUp(() {
    DiagLog.reset();
    dir = Directory.systemTemp.createTempSync('riffdiag');
  });

  tearDown(() {
    DiagLog.reset();
    dir.deleteSync(recursive: true);
  });

  test('lines reach the file as they are logged, even before init', () {
    DiagLog.add('early');
    DiagLog.init(dir.path, version: '1.0.0');
    DiagLog.add('Playing Using AudioSource.uri');
    final text = File('${dir.path}/${DiagLog.fileName}').readAsStringSync();
    expect(text, contains('=== Riff 1.0.0 started'));
    expect(text, contains('early'));
    expect(text, contains('Playing Using AudioSource.uri'));
    expect(DiagLog.tail(), hasLength(2));
  });

  test('the next launch can read what the previous one logged', () {
    DiagLog.init(dir.path, version: '1.0.0');
    DiagLog.add('first run line');
    DiagLog.reset();

    DiagLog.init(dir.path, version: '1.0.1');
    DiagLog.add('second run line');
    final previous = DiagLog.previousRun();
    expect(previous.first, startsWith('=== Riff 1.0.0 started'));
    expect(previous.last, endsWith('first run line'));
    expect(previous.join('\n'), isNot(contains('second run line')));
    expect(DiagLog.tail().single, endsWith('second run line'));
  });

  test('the file is trimmed on launch and long lines are cut', () {
    final file = File('${dir.path}/${DiagLog.fileName}');
    file.writeAsStringSync(
        List.generate(1000, (i) => 'old $i').join('\n'));
    DiagLog.init(dir.path, version: '1.0.0');
    final lines = file.readAsLinesSync();
    // 400 kept lines plus the start marker.
    expect(lines.length, 401);
    expect(lines.first, 'old 600');

    DiagLog.add('x' * 2000);
    expect(DiagLog.tail().single.length, lessThan(700));
    expect(DiagLog.tail().single, endsWith('…'));
  });

  test('a newline inside a message stays on one line', () {
    DiagLog.init(dir.path, version: '1.0.0');
    DiagLog.add('a\nb');
    expect(DiagLog.tail().single, contains('a ⏎ b'));
  });
}
