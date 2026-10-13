import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/private_session.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
  });
  tearDown(() async {
    await PrivateSession.stop();
    await Hive.box('AppPrefs').close();
  });

  test('off until started, then on for six hours, off when stopped', () async {
    expect(PrivateSession.isActive, isFalse);
    expect(PrivateSession.endsAt, isNull);

    final before = DateTime.now();
    await PrivateSession.start();
    expect(PrivateSession.isActive, isTrue);
    expect(PrivateSession.active.value, isTrue);
    final end = PrivateSession.endsAt!;
    expect(end.difference(before), greaterThanOrEqualTo(PrivateSession.length));
    expect(end.difference(DateTime.now()),
        lessThanOrEqualTo(PrivateSession.length));

    await PrivateSession.stop();
    expect(PrivateSession.isActive, isFalse);
    expect(PrivateSession.active.value, isFalse);
  });

  test('a session that ran out while the app was closed is over', () async {
    await Hive.box('AppPrefs').put(
        PrivateSession.key,
        DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch);
    PrivateSession.active.value = true; // as the switch last showed it
    expect(PrivateSession.isActive, isFalse);
    expect(PrivateSession.active.value, isFalse);
  });

  test('one still running after a restart carries on', () async {
    await Hive.box('AppPrefs').put(PrivateSession.key,
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch);
    expect(PrivateSession.isActive, isTrue);
    expect(PrivateSession.active.value, isTrue);
  });
}
