import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/sleep_shake.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MockStreamHandlerEventSink? phone;

  setUp(() {
    phone = null;
    messenger.setMockStreamHandler(
      SleepShake.channel,
      MockStreamHandler.inline(
        onListen: (_, events) => phone = events,
        onCancel: (_) => phone = null,
      ),
    );
  });
  tearDown(() {
    SleepShake.stop();
    messenger.setMockStreamHandler(SleepShake.channel, null);
  });

  test('watched only while a timed timer runs, on Android', () async {
    var shakes = 0;
    void onShake() => shakes++;

    SleepShake.follow(wanted: true, onShake: onShake, android: false);
    SleepShake.follow(wanted: false, onShake: onShake, android: true);
    await pumpEventQueue();
    expect(SleepShake.listening, isFalse);
    expect(phone, isNull);

    SleepShake.follow(wanted: true, onShake: onShake, android: true);
    // Again while watching: still one stream.
    SleepShake.follow(wanted: true, onShake: onShake, android: true);
    await pumpEventQueue();
    expect(SleepShake.listening, isTrue);
    phone!.success(null);
    phone!.success(null);
    await pumpEventQueue();
    expect(shakes, 2);

    // The timer ended or became "end of episode".
    SleepShake.follow(wanted: false, onShake: onShake, android: true);
    await pumpEventQueue();
    expect(SleepShake.listening, isFalse);
    expect(phone, isNull);
  });

  test('the switch: on by default, kept, off stops watching', () async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    addTearDown(() => Hive.box('AppPrefs').close());
    expect(SleepShake.enabled.value, isTrue);

    SleepShake.follow(wanted: true, onShake: () {}, android: true);
    await SleepShake.setEnabled(false);
    expect(Hive.box('AppPrefs').get(SleepShake.prefKey), isFalse);
    SleepShake.follow(wanted: true, onShake: () {}, android: true);
    await pumpEventQueue();
    expect(SleepShake.listening, isFalse);

    await SleepShake.setEnabled(true);
    expect(Hive.box('AppPrefs').get(SleepShake.prefKey), isTrue);
  });
}
