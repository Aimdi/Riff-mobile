import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playling_from.dart';
import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_types.dart';
import '/services/stats_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/image_widget.dart' show ImageWidget;
import '/ui/widgets/riff_sheet.dart' show RiffChoiceChip;
import '/ui/widgets/rows_reveal.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Home/home_layout.dart';

/// Riff Stats page: plays, hours, top songs/artists and daily activity,
/// computed from the local listening database only. The top songs and
/// artists are of the last 4 weeks, the last 6 months or all time, as
/// Spotify ranks them (the first two from your plays Discovery keeps).
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  StatsRange _range = StatsRange.allTime;

  /// A new range's top songs and artists fade in in place of the last's.
  late final _reveal = RowsReveal(vsync: this);

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  String _hoursLabel(int seconds) {
    final h = seconds / 3600.0;
    return h >= 100 ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
  }

  /// Plays [songs] from [id], as Spotify plays your top songs.
  void _playFrom(List<MediaItem> songs, String id) {
    final i = songs.indexWhere((m) => m.id == id);
    if (i < 0 || !Get.isRegistered<PlayerController>()) return;
    Get.find<PlayerController>()
        .playPlayListSong(songs, i,
            playfrom: PlaylingFrom(
                type: PlaylingFromType.SELECTION, name: 'topSongs'.tr))
        .then((ok) {
      if (!ok) snackOperationFailed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscovery = Get.isRegistered<DiscoveryService>();
    final range = hasDiscovery ? _range : StatsRange.allTime;
    final rows = range.days == null
        ? null
        : Get.find<DiscoveryService>().repo.playRowsSince(
            DateTime.now().subtract(Duration(days: range.days!)));
    final topSongs =
        rows == null ? StatsService.topSongs(10) : rankTopSongs(rows, 10);
    final playable = topSongsToPlay(topSongs);
    final songById = {for (final m in playable) m.id: m};
    final topArtists =
        rows == null ? StatsService.topArtists(10) : rankTopArtists(rows, 10);
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

    // Chart: the accent for the series (§ Phase 8).
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: ListView(
        padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
        children: [
          RiffPageHeader("stats".tr),
          Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: RiffSpacing.sm,
                right: HomeLayout.gutter),
            child: _TileRows([
              _StatTile(Icons.play_arrow_rounded, "${StatsService.totalPlays}",
                  "plays".tr),
              _StatTile(Icons.schedule_rounded,
                  _hoursLabel(StatsService.totalSeconds), "hours".tr),
              _StatTile(Icons.skip_next_rounded, "${StatsService.totalSkips}",
                  "skips".tr),
              _StatTile(Icons.person_rounded, "${StatsService.uniqueArtists}",
                  "artists".tr),
              if (hasDiscovery) ...[
                _StatTile(
                    Icons.explore_rounded,
                    "${(explorationRatio * 100).toStringAsFixed(0)}%",
                    "explorationRatio".tr),
                _StatTile(Icons.auto_awesome_rounded, "$keptFresh",
                    "keptFromFreshFinds".tr),
              ],
            ]),
          ),
          HomeSectionHeader("last7Days".tr),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            child: SizedBox(
              height: RiffComponentSizes.statsChart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, d) in days.indexed)
                    Expanded(
                      child: _DayBar(
                        date: DateTime.parse(d["day"] as String),
                        today: i == days.length - 1,
                        plays: d["plays"] as int,
                        fraction: (d["plays"] as int) / maxDayPlays,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasDiscovery)
            Padding(
              padding: const EdgeInsets.only(
                  left: HomeLayout.gutter,
                  top: RiffSpacing.lg,
                  right: HomeLayout.gutter),
              child: Wrap(
                spacing: RiffSpacing.sm,
                runSpacing: RiffSpacing.sm,
                children: [
                  for (final r in StatsRange.values)
                    RiffChoiceChip(
                      label: r.labelKey.tr,
                      selected: r == range,
                      onTap: () {
                        if (r != _range) _reveal.play();
                        setState(() => _range = r);
                      },
                    ),
                ],
              ),
            ),
          HomeSectionHeader(
            "topSongs".tr,
            // §5.5 text button: accent, theme type, as Recent searches'
            // Clear.
            trailing: playable.isEmpty
                ? null
                : TextButton(
                    onPressed: () => _playFrom(playable, playable.first.id),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: RiffSpacing.md),
                    ),
                    child: Text('play'.tr),
                  ),
          ),
          if (topSongs.isEmpty)
            _reveal.row(
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: HomeLayout.gutter, vertical: RiffSpacing.xs),
                child: Text("statsEmpty".tr,
                    style: homeCardSubtitleStyle(context)),
              ),
            ),
          for (final e in topSongs.asMap().entries)
            _reveal.row(
              _RankRow(
                rank: e.key + 1,
                title: '${e.value["title"]}',
                subtitle: '${e.value["artist"]}',
                count: '${e.value["plays"]}',
                // Its cover, as Spotify's top tracks list shows it.
                art: _SongArt(songById['${e.value["id"]}']),
                // Songs play from there, the rest of the list after them.
                onTap: songById.containsKey('${e.value["id"]}')
                    ? () => _playFrom(playable, '${e.value["id"]}')
                    : null,
              ),
            ),
          HomeSectionHeader("topArtists".tr),
          for (final e in topArtists.asMap().entries)
            _reveal.row(
              _RankRow(
                rank: e.key + 1,
                title: '${e.value["artist"]}',
                count: '${e.value["plays"]}',
              ),
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
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    // On the page background, outlined by a hairline (secondary text stays
    // on black for contrast).
    return Container(
      padding: const EdgeInsets.only(
          left: RiffSpacing.lg,
          top: RiffSpacing.md,
          right: RiffSpacing.md,
          bottom: RiffSpacing.md),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(
            BorderSide(color: theme.dividerColor, width: 0)),
        borderRadius: BorderRadius.circular(RiffRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon,
              size: RiffComponentSizes.statIcon,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: RiffSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                // One line: its intrinsic height (the row of tiles is as
                // tall as the taller) mustn't count it wrapped.
                child: Text(value,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(color: fg)),
              ),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: homeCardSubtitleStyle(context)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The stat tiles two to a row, each row as tall as its taller tile: a
/// label may take two lines (a small phone, large text) without spilling
/// out of a tile of fixed shape.
class _TileRows extends StatelessWidget {
  const _TileRows(this.tiles);
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: RiffSpacing.gridGap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: RiffSpacing.gridGap),
                Expanded(
                    child: i + 1 < tiles.length
                        ? tiles[i + 1]
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A top song's cover; a quiet note while the song isn't known here.
class _SongArt extends StatelessWidget {
  const _SongArt(this.song);
  final MediaItem? song;

  @override
  Widget build(BuildContext context) {
    final song = this.song;
    if (song != null) {
      return ImageWidget(
        size: RiffComponentSizes.rowArt,
        song: song,
        borderRadius: RiffRadii.xs,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(RiffRadii.xs),
      child: SizedBox.square(
        dimension: RiffComponentSizes.rowArt,
        child: ColoredBox(
          color: homeTileColor(context),
          child: Icon(Icons.music_note_rounded, color: homeMutedColor(context)),
        ),
      ),
    );
  }
}

/// One day in the last-7-days chart: count, bar and the weekday's letter
/// (today's in the text colour), as Apple's and Google's activity charts
/// label a week.
class _DayBar extends StatelessWidget {
  const _DayBar(
      {required this.date,
      required this.today,
      required this.plays,
      required this.fraction,
      required this.color});
  final DateTime date;
  final bool today;
  final int plays;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // DateTime counts Monday as 1 and Sunday as 7; the letters start on
    // Sunday.
    final letter = loc.narrowWeekdays[date.weekday % 7];
    return Semantics(
      container: true,
      label: '${loc.formatFullDate(date)}: $plays ${'plays'.tr}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.xs),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('$plays',
                style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            const SizedBox(height: RiffSpacing.xs),
            Flexible(
              child: FractionallySizedBox(
                heightFactor: fraction.clamp(0.04, 1.0),
                child: Container(
                  // Empty days: a stub in the divider (gridline) colour.
                  decoration: BoxDecoration(
                    color: plays == 0 ? theme.dividerColor : color,
                    borderRadius: BorderRadius.circular(RiffRadii.xs),
                  ),
                ),
              ),
            ),
            const SizedBox(height: RiffSpacing.xs),
            Text(letter,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: today ? theme.colorScheme.onSurface : muted)),
          ],
        ),
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
      required this.count,
      this.art,
      this.onTap});
  final int rank;
  final String title;
  final String? subtitle;
  final String count;

  /// The song's cover between the number and the title.
  final Widget? art;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = _content(context);
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: HomeLayout.gutter, vertical: RiffSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: RiffComponentSizes.statsRank,
            child: Text('$rank',
                style: theme.textTheme.titleMedium?.copyWith(
                    color: rank <= 3
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant)),
          ),
          if (art != null) ...[
            art!,
            const SizedBox(width: RiffSpacing.md),
          ],
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
          const SizedBox(width: RiffSpacing.sm),
          // Count pill: transparent with a hairline, like an unselected
          // chip (§5.6).
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: RiffSpacing.sm, vertical: RiffSpacing.xs),
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                  BorderSide(color: theme.dividerColor, width: 0)),
              borderRadius: BorderRadius.circular(RiffRadii.pill),
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
