import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/stats_service.dart';
import '/ui/navigator.dart';
import '/ui/utils/riff_tokens.dart';
import 'home_layout.dart';

/// "Your week" at the end of Home: a seven-day bar strip, the play count
/// and the top artist, computed from the local listening database.
/// Tapping opens Stats.
class HomeStatsCard extends StatelessWidget {
  const HomeStatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('DailyStats') || !Hive.isBoxOpen('SongStats')) {
      return const SizedBox.shrink();
    }
    final days = StatsService.lastDays(7);
    final plays = days.fold<int>(0, (n, d) => n + (d['plays'] as int));
    if (plays == 0) return const SizedBox.shrink();
    final top = StatsService.topArtists(1);
    final topArtist = top.isEmpty ? null : '${top.first['artist']}';
    final peak = days
        .map((d) => d['plays'] as int)
        .fold<int>(1, (m, v) => v > m ? v : m);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final fg = theme.textTheme.titleMedium?.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HomeLayout.gutter, HomeLayout.sectionTop, HomeLayout.gutter, 0),
      child: Material(
        color: homeTileColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusLg),
          side: homeTileBorder(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Get.toNamed(ScreenNavigationSetup.statsScreen,
              id: ScreenNavigationSetup.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('yourWeek'.tr,
                          style: homeSectionTitleStyle(context)
                              .copyWith(fontSize: 17)),
                      const SizedBox(height: 4),
                      Text(
                        topArtist == null
                            ? '$plays ${'plays'.tr}'
                            : '$plays ${'plays'.tr} · ${'rewindTopArtist'.tr}: $topArtist',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardSubtitleStyle(context)
                            .copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 44,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in days)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Container(
                            width: 8,
                            height: (4 + 40 * (d['plays'] as int) / peak)
                                .toDouble(),
                            decoration: BoxDecoration(
                              color: (d['plays'] as int) > 0
                                  ? accent
                                  : (fg ?? Colors.grey).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
