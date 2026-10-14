/// Where the sound plays: the phone's own output switcher (Bluetooth
/// headphones, speakers, this phone), as Spotify's and YouTube Music's
/// devices button opens one (Android).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '/utils/helper.dart';

class AudioOutput {
  AudioOutput._();

  /// MainActivity's: the switcher opens over it.
  static const channel = MethodChannel('riff/apps');

  /// Only Android has one to open.
  static bool get available => defaultTargetPlatform == TargetPlatform.android;

  /// Opens the switcher; false when none opened.
  static Future<bool> showSwitcher() async {
    if (!available) return false;
    try {
      return await channel.invokeMethod<bool>('showOutputSwitcher') ?? false;
    } catch (e) {
      printERROR('Audio output: $e');
      return false;
    }
  }
}
