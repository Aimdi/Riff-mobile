import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '/models/thumbnail.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/services/podcast_segments.dart';
import '/services/podcast_stats.dart';
import '../../widgets/snackbar.dart';
import '../Home/home_layout.dart';
import 'podcast_empty_state.dart';
import 'podcast_layout.dart';

/// "3 h 20 min" / "42 min" / "0 min".
String podcastStatsDuration(Duration d) {
  final p = splitDuration(d);
  if (p.hours > 0 && p.minutes == 0) {
    return 'statsHours'.trParams({'h': '${p.hours}'});
  }
  if (p.hours > 0) {
    return 'statsHoursMinutes'
        .trParams({'h': '${p.hours}', 'm': '${p.minutes}'});
  }
  return 'statsMinutes'.trParams({'m': '${p.minutes}'});
}

String _days(int n) =>
    n == 1 ? 'statsOneDay'.tr : 'statsDays'.trParams({'n': '$n'});

/// Podcast listening stats (podcasts only): time listened, time saved by
/// speed and by skipping, the listening streak and top shows. Shareable
/// as an image. Opened from the chart icon in the Podcasts tab header.
class PodcastStatsScreen extends StatefulWidget {
  const PodcastStatsScreen({super.key});

  @override
  State<PodcastStatsScreen> createState() => _PodcastStatsScreenState();
}

class _PodcastStatsScreenState extends State<PodcastStatsScreen> {
  final _card = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Include the last few seconds of listening.
    PodcastStatsService.flush();
  }

  Future<void> _share() async {
    try {
      final boundary =
          _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/riff-podcast-stats.png');
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')],
          text: 'podcastStatsShareText'.tr);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            snackbar(context, 'operationFailed'.tr, size: SanckBarSize.BIG));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        PodcastStatsService.rev.value;
        PodcastSegmentStore.rev.value;
        final listened = PodcastStatsService.listened;
        final empty = listened < const Duration(minutes: 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RiffPageHeader('podcastStats'.tr, actions: [
              if (!empty)
                IconButton(
                  tooltip: 'share'.tr,
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: _share,
                ),
            ]),
            Expanded(
              child: empty
                  ? PodcastEmptyState(
                      icon: Icons.insights_rounded,
                      message: 'podcastStatsEmpty'.tr,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(
                          left: HomeLayout.gutter,
                          top: RiffSpacing.sm,
                          right: HomeLayout.gutter,
                          bottom: RiffSpacing.listEnd),
                      child: RepaintBoundary(
                        key: _card,
                        child: _StatsCard(listened: listened),
                      ),
                    ),
            ),
          ],
        );
      }),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.listened});
  final Duration listened;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The headline figure is the card's one data series: accent.
    final accent = scheme.primary;
    final muted = scheme.onSurfaceVariant;
    final top = PodcastStatsService.top();
    final streak = PodcastStatsService.streak();
    // Opaque page background (the card is also shared as an image) with a
    // hairline outline.
    return Container(
      padding: const EdgeInsets.all(RiffSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(RiffRadii.lg),
        border: Border.fromBorderSide(
            BorderSide(color: theme.dividerColor, width: 0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('statsListened'.tr.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: homeMutedColor(context))),
          const SizedBox(height: RiffSpacing.xs),
          Text(podcastStatsDuration(listened),
              style: theme.textTheme.displayMedium?.copyWith(color: accent)),
          const SizedBox(height: RiffSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _Tile(
                    icon: Icons.speed_rounded,
                    label: 'statsSavedSpeed'.tr,
                    value:
                        podcastStatsDuration(PodcastStatsService.savedBySpeed)),
              ),
              const SizedBox(width: RiffSpacing.sm),
              Expanded(
                child: _Tile(
                    icon: Icons.fast_forward_rounded,
                    label: 'statsSavedSkipping'.tr,
                    value: podcastStatsDuration(PodcastSegmentStore.timeSaved)),
              ),
              const SizedBox(width: RiffSpacing.sm),
              Expanded(
                child: _Tile(
                    icon: Icons.local_fire_department_rounded,
                    label: 'statsStreak'.tr,
                    value: _days(streak)),
              ),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.xl),
            Text('statsTopShows'.tr, style: homeSectionTitleStyle(context)),
            const SizedBox(height: RiffSpacing.sm),
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: RiffSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: RiffComponentSizes.statsRankCompact,
                      child: Text('${i + 1}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: muted)),
                    ),
                    PodcastArt(
                        url: Thumbnail(top[i].artUri ?? '').medium,
                        size: RiffComponentSizes.statsShowArt),
                    const SizedBox(width: RiffSpacing.md),
                    Expanded(
                      child: Text(top[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                    ),
                    Text(
                        podcastStatsDuration(Duration(milliseconds: top[i].ms)),
                        style: homeCardSubtitleStyle(context)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: RiffSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.podcasts_rounded,
                  size: RiffComponentSizes.brandGlyph, color: muted),
              const SizedBox(width: RiffSpacing.xs),
              Text('Riff',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Hairline outline, no fill: the label's secondary grey stays on black.
    return Container(
      padding: const EdgeInsets.all(RiffSpacing.md),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(
            BorderSide(color: theme.dividerColor, width: 0)),
        borderRadius: BorderRadius.circular(RiffRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: RiffComponentSizes.statIcon,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: RiffSpacing.sm),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RiffSpacing.xxs),
          Text(label,
              maxLines: 2,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: homeMutedColor(context))),
        ],
      ),
    );
  }
}
