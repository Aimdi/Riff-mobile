import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/stats_service.dart';
import '/ui/utils/theme_controller.dart';
import '../../utils/riff_tokens.dart';
import '../Home/home_layout.dart';

/// "Riff Rewind" — a your-year-in-music style summary (ported in spirit
/// from RiPlay's Rewind + listener-level features), computed entirely
/// from the local listening database. No account, no server.
class RewindScreen extends StatelessWidget {
  const RewindScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Get.find<ThemeController>().accentColor.value;
    final plays = StatsService.totalPlays;
    final hours = (StatsService.totalSeconds / 3600.0);
    final topArtists = StatsService.topArtists(1);
    final topSongs = StatsService.topSongs(1);
    final level = StatsService.listenerLevel;
    final explored = StatsService.uniqueArtists;

    if (plays < 5) {
      return Scaffold(
        backgroundColor: Theme.of(context).canvasColor,
        body: Column(
          children: [
            RiffPageHeader("riffRewind".tr),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text("rewindNotEnough".tr,
                      textAlign: TextAlign.center,
                      style: homeCardSubtitleStyle(context)
                          .copyWith(fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hoursLabel =
        hours >= 100 ? hours.toStringAsFixed(0) : hours.toStringAsFixed(1);
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 160),
        children: [
          RiffPageHeader("riffRewind".tr, subtitle: "riffRewindDes".tr),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                HomeLayout.gutter, 10, HomeLayout.gutter, 0),
            child: _hero(context, accent, level),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                HomeLayout.gutter, 12, HomeLayout.gutter, 0),
            child: Row(
              children: [
                _stat(context, accent, "$plays", "rewindTotalPlays".tr),
                const SizedBox(width: 10),
                _stat(context, accent, hoursLabel, "rewindTotalHours".tr),
                const SizedBox(width: 10),
                _stat(context, accent, "$explored", "rewindArtistsExplored".tr),
              ],
            ),
          ),
          if (topArtists.isNotEmpty)
            _highlight(context, accent, Icons.person_rounded,
                "rewindTopArtist".tr, '${topArtists.first["artist"]}',
                "${topArtists.first["plays"]}"),
          if (topSongs.isNotEmpty)
            _highlight(context, accent, Icons.music_note_rounded,
                "rewindTopSong".tr, '${topSongs.first["title"]}',
                "${topSongs.first["plays"]}"),
        ],
      ),
    );
  }

  /// Accent card with the listener level.
  Widget _hero(BuildContext context, Color accent, int level) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RiffTokens.radiusLg),
        gradient: LinearGradient(
          colors: [accent.withOpacity(0.9), accent.withOpacity(0.25)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
            ),
            child: Center(
              child: Text("$level",
                  style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: accent)),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text("rewindListenerLevel".tr,
                style: const TextStyle(
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, Color accent, String value, String label) {
    return Expanded(
      child: Container(
        height: 104,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: homeTileColor(context),
          borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, color: accent)),
            ),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: homeCardSubtitleStyle(context).copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _highlight(BuildContext context, Color accent, IconData icon,
      String heading, String value, String plays) {
    final fg = Theme.of(context).textTheme.titleMedium?.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HomeLayout.gutter, 12, HomeLayout.gutter, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: homeTileColor(context),
          borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accent)),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: fg)),
                  Text("$plays ${"plays".tr}",
                      style: homeCardSubtitleStyle(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
