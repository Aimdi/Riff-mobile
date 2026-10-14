import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the phone's connection costs data (mobile data, a metered
/// hotspot), so big downloads can wait for Wi-Fi as AntennaPod and Pocket
/// Casts let them.
class NetworkKind {
  NetworkKind._();

  static const channel = MethodChannel('riff/network');

  /// The last answer [isMetered] gave (false until it's first asked), for
  /// what can't wait for a fresh one.
  static bool lastMetered = false;

  /// True on mobile data, and on Android when it can't tell (so nothing
  /// big goes over mobile data by mistake); false elsewhere (desktop).
  static Future<bool> isMetered() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return lastMetered = false;
    }
    try {
      return lastMetered =
          await channel.invokeMethod<bool>('isMetered') ?? true;
    } catch (_) {
      return lastMetered = true;
    }
  }
}
