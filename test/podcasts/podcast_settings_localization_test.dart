import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_library.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/spotify_home.dart';
import 'package:harmonymusic/ui/screens/Home/home_sections.dart';
import 'package:harmonymusic/ui/screens/Home/home_station_chips.dart';
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
      'lib/ui/screens/Podcasts/podcast_segment_ui.dart',
      'lib/ui/player/player_controller.dart',
      'lib/ui/player/components/podcast_transcript_sheet.dart',
      'lib/ui/screens/Podcasts/podcast_bookmarks_ui.dart',
      'lib/ui/screens/Podcasts/podcasts_library.dart',
      'lib/ui/screens/Podcasts/podcast_library_ui.dart',
      'lib/ui/screens/Podcasts/podcast_inbox_screen.dart',
      'lib/ui/screens/Podcasts/podcast_queue_screen.dart',
      'lib/ui/screens/Podcasts/podcast_subs_screen.dart',
      'lib/ui/screens/Podcasts/podcast_show_view.dart',
      'lib/ui/screens/Podcasts/podcast_stats_screen.dart',
      // Not podcast-only, but the same check: Never play and CSV import.
      'lib/ui/screens/Settings/blacklist_screen.dart',
      // Home (redesign v2).
      'lib/ui/screens/Home/home_screen.dart',
      'lib/ui/screens/Home/home_feed_data.dart',
      'lib/ui/screens/Home/home_jump_back_in.dart',
      'lib/ui/screens/Home/home_station_chips.dart',
      'lib/ui/screens/Home/home_speed_dial.dart',
      'lib/ui/screens/Home/home_hero_carousel.dart',
      'lib/ui/screens/Home/home_shelves.dart',
      'lib/ui/screens/Home/home_stats_card.dart',
      'lib/ui/screens/Home/home_sections.dart',
      'lib/ui/screens/Home/home_layout_screen.dart',
      'lib/ui/screens/Home/explore_screen.dart',
      'lib/ui/widgets/discovery/riff_wave_hero.dart',
      'lib/ui/screens/Settings/webdav_sync_screen.dart',
      'lib/ui/screens/Plugins/spotify_bridge_screen.dart',
      'lib/ui/screens/Plugins/spotify_pages.dart',
      'lib/ui/screens/Plugins/spotify_widgets.dart',
      'lib/ui/screens/Plugins/spotify_connect_ui.dart',
      'lib/ui/widgets/spotify_import_dialog.dart',
      'lib/ui/widgets/songinfo_bottom_sheet.dart',
    ])
      ..._trKeys(File(f).readAsStringSync()),
    // Built from the enum name: 'voiceBoost_${v.name}'.tr
    for (final v in PodcastVoiceBoost.values) 'voiceBoost_${v.name}',
    // Segment category / action / source names built from enums.
    for (final c in SegmentCategory.values) ...[c.labelKey, '${c.labelKey}Des'],
    for (final a in SegmentAction.values) 'segAction_${a.name}',
    for (final s in SegmentSource.values) 'segSource_${s.name}',
    // Library filter chips and auto-delete choices, from enum names.
    for (final f in EpisodeFilter.values) 'episodeFilter_${f.name}',
    for (final p in AutoDeletePolicy.values) 'autoDelete_${p.name}',
    // Home: station chips and section names come from data.
    for (final s in homeStations) s.key,
    for (final s in HomeSection.values) s.labelKey,
    for (final s in SpotifyShelfId.values) s.titleKey,
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
