/// Download on Wi-Fi only (Spotify's "Download using cellular" turned off,
/// YouTube Music's and Apple Music's Wi-Fi-only downloads): on mobile data,
/// song downloads wait for Wi-Fi and go on by themselves once it's there.
/// Off by default.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/network_kind.dart';

class WifiOnlyDownloads {
  WifiOnlyDownloads._();

  /// AppPrefs key.
  static const key = 'downloadOnWifiOnly';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// For the Settings switch.
  static final enabled = RxBool(_prefs?.get(key) == true);

  static Future<void> set(bool on) async {
    enabled.value = on;
    await _prefs?.put(key, on);
  }

  /// How long a waiting download goes before it looks at the connection
  /// again (turning the setting off ends the wait at once).
  @visibleForTesting
  static Duration poll = const Duration(seconds: 15);

  /// Whether the connection costs data.
  @visibleForTesting
  static Future<bool> Function() metered = NetworkKind.isMetered;

  /// Holds a download while it must wait: Wi-Fi only, on mobile data.
  /// [onWait] once the waiting starts. True to go on; false when [wanted]
  /// says the download was called off meanwhile.
  static Future<bool> waitForWifi(
      {required bool Function() wanted, void Function()? onWait}) async {
    var waiting = false;
    while (enabled.value && await metered()) {
      if (!wanted()) return false;
      if (!waiting) {
        waiting = true;
        onWait?.call();
      }
      await _sleep();
    }
    return !waiting || wanted();
  }

  /// [poll], or less when the setting changes.
  static Future<void> _sleep() {
    final done = Completer<void>();
    void wake([_]) {
      if (!done.isCompleted) done.complete();
    }

    final timer = Timer(poll, wake);
    final changes = enabled.listen(wake);
    return done.future.whenComplete(() {
      timer.cancel();
      changes.cancel();
    });
  }
}
