/// In-app voice search, as YouTube Music, Spotify and Apple Music have a
/// mic in their search field: the phone's own speech recognition ("Speak
/// now") listens, and Riff searches what it heard (Android).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '/utils/helper.dart';

class VoiceInput {
  VoiceInput._();

  static const channel = MethodChannel('riff/apps');

  /// What [available] last answered; null before it first has.
  static bool? known;

  static Future<bool>? _asking;

  /// Whether the phone can listen (it has speech recognition); asked
  /// once. False off Android.
  static Future<bool> available() => _asking ??= _ask();

  static Future<bool> _ask() async {
    if (defaultTargetPlatform != TargetPlatform.android) return known = false;
    try {
      return known = await channel.invokeMethod<bool>('canListen') ?? false;
    } catch (e) {
      printERROR('Voice input: $e');
      // Not an answer: asked again next time.
      _asking = null;
      return false;
    }
  }

  /// Listens once, [prompt] under the phone's "Speak now", and returns
  /// what it heard; null when it heard nothing (cancelled, no match).
  static Future<String?> listen({String? prompt}) async {
    try {
      final heard =
          (await channel.invokeMethod<String>('listen', {'prompt': prompt}))
              ?.trim();
      return heard == null || heard.isEmpty ? null : heard;
    } catch (e) {
      printERROR('Voice input: $e');
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    known = null;
    _asking = null;
  }
}
