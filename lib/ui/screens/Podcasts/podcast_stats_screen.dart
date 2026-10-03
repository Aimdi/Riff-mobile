import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '/models/thumbnail.dart';
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
                      padding: const EdgeInsets.fromLTRB(
                          HomeLayout.gutter, 8, HomeLayout.gutter, 200),
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
    final accent = theme.colorScheme.secondary;
    final top = PodcastStatsService.top();
    final streak = PodcastStatsService.streak();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.fromBorderSide(homeTileBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('statsListened'.tr.toUpperCase(),
              style: homeCardSubtitleStyle(context).copyWith(
                  fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(podcastStatsDuration(listened),
              style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: accent)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Tile(
                    icon: Icons.speed_rounded,
                    label: 'statsSavedSpeed'.tr,
                    value: podcastStatsDuration(
                        PodcastStatsService.savedBySpeed)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                    icon: Icons.fast_forward_rounded,
                    label: 'statsSavedSkipping'.tr,
                    value:
                        podcastStatsDuration(PodcastSegmentStore.timeSaved)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                    icon: Icons.local_fire_department_rounded,
                    label: 'statsStreak'.tr,
                    value: _days(streak)),
              ),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('statsTopShows'.tr, style: homeSectionTitleStyle(context)),
            const SizedBox(height: 8),
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}',
                          style: homeCardSubtitleStyle(context).copyWith(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                    PodcastArt(
                        url: Thumbnail(top[i].artUri ?? '').medium, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(top[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    Text(podcastStatsDuration(Duration(milliseconds: top[i].ms)),
                        style: homeCardSubtitleStyle(context)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.podcasts_rounded, size: 14, color: accent),
              const SizedBox(width: 4),
              Text('Riff',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: accent)),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: homeTileColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              style: homeCardSubtitleStyle(context).copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}
