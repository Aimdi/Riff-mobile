import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_types.dart';
import '/services/stats_service.dart';
import '/ui/theme/riff_spacing.dart';
import '../../utils/riff_tokens.dart';
import '../Home/home_layout.dart';

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

    final accent = Theme.of(context).colorScheme.secondary;
    final hasDiscovery = Get.isRegistered<DiscoveryService>();
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 160),
        children: [
          RiffPageHeader("stats".tr),
          Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: RiffSpacing.sm,
                right: HomeLayout.gutter),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                _StatTile(Icons.play_arrow_rounded,
                    "${StatsService.totalPlays}", "plays".tr),
                _StatTile(Icons.schedule_rounded,
                    _hoursLabel(StatsService.totalSeconds), "hours".tr),
                _StatTile(Icons.skip_next_rounded, "${StatsService.totalSkips}",
                    "skips".tr),
                _StatTile(Icons.person_rounded, "${StatsService.uniqueArtists}",
                    "topArtists".tr),
                if (hasDiscovery) ...[
                  _StatTile(
                      Icons.explore_rounded,
                      "${(explorationRatio * 100).toStringAsFixed(0)}%",
                      "explorationRatio".tr),
                  _StatTile(Icons.auto_awesome_rounded, "$keptFresh",
                      "keptFromFreshFinds".tr),
                ],
              ],
            ),
          ),
          HomeSectionHeader("last7Days".tr),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            child: SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: _DayBar(
                        label: (d["day"] as String).substring(5),
                        plays: d["plays"] as int,
                        fraction: (d["plays"] as int) / maxDayPlays,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          HomeSectionHeader("topSongs".tr),
          if (topSongs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: HomeLayout.gutter, vertical: 6),
              child:
                  Text("statsEmpty".tr, style: homeCardSubtitleStyle(context)),
            ),
          for (final e in topSongs.asMap().entries)
            _RankRow(
              rank: e.key + 1,
              title: '${e.value["title"]}',
              subtitle: '${e.value["artist"]}',
              count: '${e.value["plays"]}',
            ),
          HomeSectionHeader("topArtists".tr),
          for (final e in topArtists.asMap().entries)
            _RankRow(
              rank: e.key + 1,
              title: '${e.value["artist"]}',
              count: '${e.value["plays"]}',
            ),
          if (rising.isNotEmpty) ...[
            HomeSectionHeader("topRisingArtists".tr),
            for (final e in rising.asMap().entries)
              _RankRow(
                rank: e.key + 1,
                title: '${e.value['key']}',
                count: '${e.value['score']}',
              ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color;
    return Container(
      padding: const EdgeInsets.only(
          left: RiffSpacing.lg,
          top: RiffSpacing.md,
          right: RiffSpacing.md,
          bottom: RiffSpacing.md),
      decoration: BoxDecoration(
        color: homeTileColor(context),
        borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(color: fg)),
              ),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: homeCardSubtitleStyle(context)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One day in the last-7-days chart: count, bar and date.
class _DayBar extends StatelessWidget {
  const _DayBar(
      {required this.label,
      required this.plays,
      required this.fraction,
      required this.color});
  final String label;
  final int plays;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$plays',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Flexible(
            child: FractionallySizedBox(
              heightFactor: fraction.clamp(0.04, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: plays == 0 ? homeTileColor(context) : color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Ranked row: number, title (and subtitle), count pill.
class _RankRow extends StatelessWidget {
  const _RankRow(
      {required this.rank,
      required this.title,
      this.subtitle,
      required this.count});
  final int rank;
  final String title;
  final String? subtitle;
  final String count;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: HomeLayout.gutter, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('$rank',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: rank <= 3
                        ? Theme.of(context).colorScheme.secondary
                        : homeMutedColor(context))),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: fg)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardSubtitleStyle(context)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: homeTileColor(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(count,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}
