import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_types.dart';
import '/services/stats_service.dart';

/// Riff Stats page: plays, hours, top songs/artists and daily activity,
/// computed from the local listening database only.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  String _hoursLabel(int seconds) {
    final h = seconds / 3600.0;
    return h >= 100 ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final topSongs = StatsService.topSongs(10);
    final topArtists = StatsService.topArtists(10);
    final days = StatsService.lastDays(7);
    final maxDayPlays = days.fold<int>(
        1, (m, d) => (d["plays"] as int) > m ? d["plays"] as int : m);

    // Discovery insights
    double explorationRatio = 0;
    List<Map<String, dynamic>> rising = [];
    int keptFresh = 0;
    if (Get.isRegistered<DiscoveryService>()) {
      final disc = Get.find<DiscoveryService>();
      final events = disc.repo.recentEvents(limit: 500);
      final plays = events
          .where((e) =>
              e.event == DiscoveryEventKind.playStarted ||
              e.event == DiscoveryEventKind.playEnded)
          .toList();
      if (plays.isNotEmpty) {
        final firstTime = plays.where((e) {
          // Approximate: discover/radio/fresh sources count as exploration
          return e.source == DiscoverySource.discover ||
              e.source == DiscoverySource.dailyMix ||
              e.source == DiscoverySource.similar ||
              e.source == DiscoverySource.radio;
        }).length;
        explorationRatio = firstTime / plays.length;
      }
      final snap = disc.debugSnapshot();
      rising = List<Map<String, dynamic>>.from(
          (snap['artists'] as List? ?? []).take(5));
      keptFresh = events
          .where((e) =>
              e.surface == DiscoverySurface.freshFinds &&
              (e.event == DiscoveryEventKind.thumbsUp ||
                  e.event == DiscoveryEventKind.favorite ||
                  e.event == DiscoveryEventKind.playlistAdd))
          .length;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 70),
        child: ListView(
          children: [
            Text("stats".tr, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            Row(
              children: [
                _statCard(context, "${StatsService.totalPlays}", "plays".tr),
                const SizedBox(width: 10),
                _statCard(context, _hoursLabel(StatsService.totalSeconds),
                    "hours".tr),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statCard(context, "${StatsService.totalSkips}", "skips".tr),
                const SizedBox(width: 10),
                _statCard(
                    context,
                    "${StatsService.uniqueArtists}",
                    "topArtists".tr),
              ],
            ),
            if (Get.isRegistered<DiscoveryService>()) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _statCard(context, "${(explorationRatio * 100).toStringAsFixed(0)}%",
                      "explorationRatio".tr),
                  const SizedBox(width: 10),
                  _statCard(context, "$keptFresh", "keptFromFreshFinds".tr),
                ],
              ),
              if (rising.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text("topRisingArtists".tr,
                    style: Theme.of(context).textTheme.titleMedium),
                ...rising.map((a) => ListTile(
                      visualDensity: const VisualDensity(vertical: -3),
                      contentPadding: EdgeInsets.zero,
                      title: Text("${a['key']}"),
                      trailing: Text("${a['score']}"),
                    )),
              ],
            ],
            const SizedBox(height: 25),
            Text("last7Days".tr,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...days.map((d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 85,
                          child: Text((d["day"] as String).substring(5),
                              style: Theme.of(context).textTheme.bodyMedium)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 10,
                            value: (d["plays"] as int) / maxDayPlays,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                      ),
                      SizedBox(
                          width: 40,
                          child: Text("  ${d["plays"]}",
                              style: Theme.of(context).textTheme.bodyMedium)),
                    ],
                  ),
                )),
            const SizedBox(height: 25),
            Text("topSongs".tr,
                style: Theme.of(context).textTheme.titleMedium),
            if (topSongs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text("statsEmpty".tr,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ...topSongs.asMap().entries.map((e) => ListTile(
                  visualDensity: const VisualDensity(vertical: -3),
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                      width: 25,
                      child: Text("${e.key + 1}",
                          style: Theme.of(context).textTheme.titleMedium)),
                  title: Text(e.value["title"], maxLines: 1),
                  subtitle: Text(e.value["artist"], maxLines: 1),
                  trailing: Text("${e.value["plays"]}",
                      style: Theme.of(context).textTheme.titleMedium),
                )),
            const SizedBox(height: 25),
            Text("topArtists".tr,
                style: Theme.of(context).textTheme.titleMedium),
            ...topArtists.asMap().entries.map((e) => ListTile(
                  visualDensity: const VisualDensity(vertical: -3),
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                      width: 25,
                      child: Text("${e.key + 1}",
                          style: Theme.of(context).textTheme.titleMedium)),
                  title: Text(e.value["artist"], maxLines: 1),
                  trailing: Text("${e.value["plays"]}",
                      style: Theme.of(context).textTheme.titleMedium),
                )),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _statCard(BuildContext context, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
