import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/stats_service.dart';
import '/ui/utils/theme_controller.dart';

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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text("rewindNotEnough".tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: ListView(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 70, bottom: 120),
        children: [
          Text("riffRewind".tr,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: accent, fontSize: 34)),
          const SizedBox(height: 4),
          Text("riffRewindDes".tr,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 30),
          _levelBadge(context, accent, level),
          const SizedBox(height: 30),
          _bigStat(context, accent, "$plays", "rewindTotalPlays".tr),
          _bigStat(context, accent, hours >= 100 ? hours.toStringAsFixed(0)
              : hours.toStringAsFixed(1), "rewindTotalHours".tr),
          _bigStat(context, accent, "$explored", "rewindArtistsExplored".tr),
          if (topArtists.isNotEmpty)
            _highlight(context, accent, "rewindTopArtist".tr,
                topArtists.first["artist"], "${topArtists.first["plays"]}"),
          if (topSongs.isNotEmpty)
            _highlight(context, accent, "rewindTopSong".tr,
                topSongs.first["title"], "${topSongs.first["plays"]}"),
        ],
      ),
    );
  }

  Widget _levelBadge(BuildContext context, Color accent, int level) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [accent, accent.withOpacity(0.4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text("$level",
                  style: const TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
            ),
          ),
          const SizedBox(height: 10),
          Text("rewindListenerLevel".tr,
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _bigStat(
      BuildContext context, Color accent, String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 40, fontWeight: FontWeight.bold, color: accent)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }

  Widget _highlight(BuildContext context, Color accent, String heading,
      String value, String plays) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: accent)),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 2,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text("$plays ${"plays".tr}",
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
