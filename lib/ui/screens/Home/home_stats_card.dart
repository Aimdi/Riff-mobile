import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/stats_service.dart';
import '/ui/navigator.dart';
import 'home_metrics.dart';

/// "Your week": plays and top artist (music only) over the last seven
/// days, with a small bar chart. Tapping opens Stats.
class HomeStatsCard extends StatelessWidget {
  const HomeStatsCard({super.key});

  void _open() => Get.toNamed(ScreenNavigationSetup.statsScreen,
      id: ScreenNavigationSetup.id);

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
    final line1 = '$plays ${'plays'.tr}';
    final line2 =
        topArtist == null ? null : '${'rewindTopArtist'.tr}: $topArtist';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RiffSectionHeader('yourWeek'.tr, onSeeAll: _open),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.gutter),
          child: Semantics(
            button: true,
            label: [line1, if (line2 != null) line2].join('. '),
            excludeSemantics: true,
            child: Material(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(RiffSizes.shelfRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _open,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: RiffSizes.weekHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface)),
                              if (line2 != null) ...[
                                const SizedBox(height: 2),
                                Text(line2,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: riffMuted(context))),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          height: 48,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final d in days)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Container(
                                    width: 8,
                                    height: (4 + 44 * (d['plays'] as int) / peak)
                                        .toDouble(),
                                    decoration: BoxDecoration(
                                      color: (d['plays'] as int) > 0
                                          ? accent
                                          : theme.colorScheme.onSurface
                                              .withOpacity(0.15),
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
            ),
          ),
        ),
      ],
    );
  }
}
