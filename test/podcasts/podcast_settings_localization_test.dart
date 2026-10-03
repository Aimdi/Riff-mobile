import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:harmonymusic/utils/get_localization.dart';

/// `.tr` falls back to the key itself, so a missing string ships as
/// "trimSilenceDes" on screen. Every key the podcast playback screens use
/// must exist in English, in both en.json and the generated map.
Set<String> _trKeys(String source) => RegExp(r"'([A-Za-z0-9_]+)'\.tr\b")
    .allMatches(source)
    .map((m) => m.group(1)!)
    .toSet();

void main() {
  final en = Languages().keys['en']!;
  final enJson = jsonDecode(File('localization/en.json').readAsStringSync())
      as Map<String, dynamic>;

  final keys = <String>{
    for (final f in const [
      'lib/ui/screens/Podcasts/podcast_playback_controls.dart',
      'lib/ui/screens/Podcasts/podcast_settings_screen.dart',
      'lib/ui/widgets/sleep_timer_bottom_sheet.dart',
    ])
      ..._trKeys(File(f).readAsStringSync()),
    // Built from the enum name: 'voiceBoost_${v.name}'.tr
    for (final v in PodcastVoiceBoost.values) 'voiceBoost_${v.name}',
  };

  test('podcast playback strings exist in English', () {
    expect(keys, isNotEmpty);
    for (final k in keys) {
      expect(en[k], isNotNull, reason: 'missing in get_localization en: $k');
      expect(en[k]!.trim(), isNotEmpty, reason: 'blank: $k');
      expect(enJson[k], en[k], reason: 'en.json drifted for $k');
    }
  });
}
