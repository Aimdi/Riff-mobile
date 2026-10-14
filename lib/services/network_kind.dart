import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the phone's connection costs data (mobile data, a metered
/// hotspot), so big downloads can wait for Wi-Fi as AntennaPod and Pocket
/// Casts let them.
class NetworkKind {
  NetworkKind._();

  static const channel = MethodChannel('riff/network');

  /// True on mobile data, and on Android when it can't tell (so nothing
  /// big goes over mobile data by mistake); false elsewhere (desktop).
  static Future<bool> isMetered() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('isMetered') ?? true;
    } catch (_) {
      return true;
    }
  }
}
