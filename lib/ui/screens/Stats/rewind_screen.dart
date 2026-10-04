import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/stats_service.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Home/home_layout.dart';

/// "Riff Rewind" — a your-year-in-music style summary (ported in spirit
/// from RiPlay's Rewind + listener-level features), computed entirely
/// from the local listening database. No account, no server.
class RewindScreen extends StatelessWidget {
  const RewindScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
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
                  padding: const EdgeInsets.all(RiffSpacing.x3l),
                  child: Text("rewindNotEnough".tr,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: homeMutedColor(context))),
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
        padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
        children: [
          RiffPageHeader("riffRewind".tr, subtitle: "riffRewindDes".tr),
          Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: RiffSpacing.md,
                right: HomeLayout.gutter),
            child: _hero(context, accent, level),
          ),
          Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: RiffSpacing.md,
                right: HomeLayout.gutter),
            child: Row(
              children: [
                _stat(context, accent, "$plays", "rewindTotalPlays".tr),
                const SizedBox(width: RiffSpacing.sm),
                _stat(context, accent, hoursLabel, "rewindTotalHours".tr),
                const SizedBox(width: RiffSpacing.sm),
                _stat(context, accent, "$explored", "rewindArtistsExplored".tr),
              ],
            ),
          ),
          if (topArtists.isNotEmpty)
            _highlight(
                context,
                accent,
                Icons.person_rounded,
                "rewindTopArtist".tr,
                '${topArtists.first["artist"]}',
                "${topArtists.first["plays"]}"),
          if (topSongs.isNotEmpty)
            _highlight(
                context,
                accent,
                Icons.music_note_rounded,
                "rewindTopSong".tr,
                '${topSongs.first["title"]}',
                "${topSongs.first["plays"]}"),
        ],
      ),
    );
  }

  /// Accent card with the listener level (Rewind's one decorative
  /// gradient).
  Widget _hero(BuildContext context, Color accent, int level) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: RiffSpacing.xl, vertical: RiffSpacing.xxl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RiffRadii.lg),
        gradient: LinearGradient(
          colors: [accent.withOpacity(0.9), accent.withOpacity(0.25)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: RiffComponentSizes.rewindLevel,
            height: RiffComponentSizes.rewindLevel,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.onPrimary,
            ),
            child: Center(
              child: Text("$level",
                  style:
                      theme.textTheme.displayMedium?.copyWith(color: accent)),
            ),
          ),
          const SizedBox(width: RiffSpacing.lg),
          Expanded(
            child: Text("rewindListenerLevel".tr,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.onPrimary)),
          ),
        ],
      ),
    );
  }

  /// Hairline outline on the page background (Phase 8: structure from
  /// hairlines; secondary text stays on black).
  BoxDecoration _outlined(BuildContext context) => BoxDecoration(
        border: Border.fromBorderSide(
            BorderSide(color: Theme.of(context).dividerColor, width: 0)),
        borderRadius: BorderRadius.circular(RiffRadii.sm),
      );

  Widget _stat(BuildContext context, Color accent, String value, String label) {
    return Expanded(
      child: Container(
        height: RiffComponentSizes.rewindStat,
        padding: const EdgeInsets.all(RiffSpacing.md),
        decoration: _outlined(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface)),
            ),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: homeCardSubtitleStyle(context)),
          ],
        ),
      ),
    );
  }

  Widget _highlight(BuildContext context, Color accent, IconData icon,
      String heading, String value, String plays) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.md,
          right: HomeLayout.gutter),
      child: Container(
        padding: const EdgeInsets.all(RiffSpacing.lg),
        decoration: _outlined(context),
        child: Row(
          children: [
            Container(
              width: RiffComponentSizes.rowArt,
              height: RiffComponentSizes.rowArt,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(RiffRadii.sm),
              ),
              child: Icon(icon, color: scheme.onSurface),
            ),
            const SizedBox(width: RiffSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: RiffSpacing.xxs),
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: fg)),
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
