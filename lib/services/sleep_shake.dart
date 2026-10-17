/// Shake the phone to restart the sleep timer, as in Pocket Casts and
/// AntennaPod: while a timed sleep timer runs (Android, switch on), a shake
/// sets it back to the length it was started with, and the phone buzzes so
/// you know it took (ShakeChannel.kt). Works with the screen off.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

class SleepShake {
  SleepShake._();

  static const prefKey = 'sleepTimerShakeRestart';
  static const channel = EventChannel('riff/shake');

  /// On unless switched off.
  static final enabled = RxBool(_stored());

  static bool _stored() =>
      !Hive.isBoxOpen('AppPrefs') || Hive.box('AppPrefs').get(prefKey) != false;

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    if (Hive.isBoxOpen('AppPrefs')) await Hive.box('AppPrefs').put(prefKey, on);
  }

  static StreamSubscription<Object?>? _shakes;

  /// Whether the phone is being watched for shakes.
  static bool get listening => _shakes != null;

  /// Watches for shakes while [wanted] (a timed sleep timer runs) and the
  /// switch is on, calling [onShake] for each; stops otherwise. [android]
  /// is for tests.
  static void follow(
      {required bool wanted, required void Function() onShake, bool? android}) {
    if (!wanted || !enabled.value || !(android ?? GetPlatform.isAndroid)) {
      stop();
      return;
    }
    _shakes ??= channel
        .receiveBroadcastStream()
        .listen((_) => onShake(), onError: (Object _) => stop());
  }

  static void stop() {
    _shakes?.cancel();
    _shakes = null;
  }
}
