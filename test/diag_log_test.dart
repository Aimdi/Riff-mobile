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

  test('a long session does not grow the file without bound', () {
    DiagLog.init(dir.path, version: '1.0.0');
    for (var i = 0; i < 5000; i++) {
      DiagLog.add('line $i');
    }
    final file = File('${dir.path}/${DiagLog.fileName}');
    final bytes = file.readAsBytesSync();
    // Rewound after the rewrite: no hole of zero bytes before new lines.
    expect(bytes.contains(0), isFalse);
    final lines = file.readAsLinesSync();
    expect(lines.length, lessThan(2100));
    expect(lines.first, startsWith('=== Riff 1.0.0 started'));
    expect(lines.last, endsWith('line 4999'));

    // The next launch still sees how this run ended.
    DiagLog.reset();
    DiagLog.init(dir.path, version: '1.0.1');
    final previous = DiagLog.previousRun();
    expect(previous, hasLength(150));
    expect(previous.last, endsWith('line 4999'));
  });

  test('a log with malformed UTF-8 is still read and written', () {
    final file = File('${dir.path}/${DiagLog.fileName}');
    file.writeAsBytesSync([
      ...'=== Riff 0.9 started ===\nbefore crash ⏎'.codeUnits.take(30),
      0xE2, 0x8F, // a multi-byte character cut short
      10,
    ]);
    DiagLog.init(dir.path, version: '1.0.0');
    DiagLog.add('after');
    expect(DiagLog.previousRun().first, '=== Riff 0.9 started ===');
    expect(file.readAsStringSync(), contains('after'));
  });

  test('a newline inside a message stays on one line', () {
    DiagLog.init(dir.path, version: '1.0.0');
    DiagLog.add('a\nb');
    expect(DiagLog.tail().single, contains('a ⏎ b'));
  });
}
