import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/crash_report.dart';

void main() {
  test('only new records with a reason are shown', () {
    expect(CrashReport.pick(null, 0), isNull);
    expect(CrashReport.pick({'reason': 'crash', 'timestamp': 5}, 5), isNull);
    expect(CrashReport.pick({'reason': '', 'timestamp': 9}, 5), isNull);
    expect(CrashReport.pick({'reason': 'native crash', 'timestamp': 9}, 5),
        isNotNull);
  });

  test('report text has version, reason and trace', () {
    final text = CrashReport.format(
        {'reason': 'crash', 'timestamp': 0, 'description': 'boom', 'trace': 'at x'},
        'V1.7.109');
    expect(text, contains('Riff V1.7.109 — crash'));
    expect(text, contains('Details: boom'));
    expect(text, contains('at x'));
  });

  test('report text includes the log the app wrote before the exit', () {
    final text = CrashReport.format(
        {'reason': 'crash', 'timestamp': 0},
        'V1.7.111',
        log: ['12:00:00.000 I Requested id : abc', '12:00:01.000 I Playing Using AudioSource.uri']);
    expect(text, contains('Log before the exit:'));
    expect(text, contains('Playing Using AudioSource.uri'));
    expect(
        CrashReport.format({'reason': 'crash', 'timestamp': 0}, 'V1'),
        isNot(contains('Log before the exit')));
  });
}
