import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_types.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/snackbar.dart';
import '/ui/theme/palettes/home_stations.dart';
import '/ui/theme/riff_tokens.dart';
import 'home_metrics.dart';

/// One station under Riff Wave. Every chip starts playback.
class HomeStation {
  const HomeStation(this.key, this.icon, this.colors, {this.query});
  final String key;
  final IconData icon;
  final List<Color> colors;

  /// YouTube Music search for a featured playlist (mood stations); null
  /// for Riff's own generators.
  final String? query;
}

const homeStations = [
  HomeStation(
      'freshFinds', Icons.auto_awesome_rounded, HomeStationPalette.freshFinds),
  HomeStation(
      'rediscover', Icons.replay_rounded, HomeStationPalette.rediscover),
  HomeStation(
      'stationEnergize', Icons.bolt_rounded, HomeStationPalette.energize,
      query: 'energize mix'),
  HomeStation('stationFeelGood', Icons.sentiment_satisfied_alt_rounded,
      HomeStationPalette.feelGood,
      query: 'feel good mix'),
  HomeStation('stationRelax', Icons.spa_rounded, HomeStationPalette.relax,
      query: 'relax chill mix'),
  HomeStation('stationWorkout', Icons.fitness_center_rounded,
      HomeStationPalette.workout,
      query: 'workout mix'),
];

/// The one chip row on Home, 12dp under Riff Wave: Fresh finds,
/// Rediscover and four moods. Scrolls sideways; the last visible chip is
/// cut at the edge so the row reads as scrollable.
class RiffStationChips extends StatefulWidget {
  const RiffStationChips({super.key});

  @override
  State<RiffStationChips> createState() => _RiffStationChipsState();
}

class _RiffStationChipsState extends State<RiffStationChips> {
  String? _busy;

  Future<void> _start(HomeStation station) async {
    if (_busy != null) return;
    setState(() => _busy = station.key);
    final messenger = ScaffoldMessenger.of(context);
    void say(String key) => messenger
        .showSnackBar(snackbar(context, key.tr, size: SanckBarSize.MEDIUM));
    try {
      final ok = station.query == null
          ? await _playGenerated(station.key)
          : await _playMood(station.query!);
      if (!ok && mounted) say('mixEmpty');
    } catch (_) {
      if (mounted) say('networkError');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Fresh finds / Rediscover from the discovery engine.
  Future<bool> _playGenerated(String key) async {
    if (!Get.isRegistered<DiscoveryService>()) return false;
    final disc = Get.find<DiscoveryService>();
    final List<MediaItem> tracks = key == 'freshFinds'
        ? await disc.engine.freshFinds()
        : await disc.engine.rediscover();
    if (tracks.isEmpty) return false;
    final source = key == 'freshFinds'
        ? DiscoverySource.freshFinds
        : DiscoverySource.discover;
    return Get.find<PlayerController>()
        .playPlayListSong(DiscoveryService.tagAll(tracks, source), 0);
  }

  /// A mood: the first featured playlist YouTube Music finds for it.
  Future<bool> _playMood(String query) async {
    final res = await Get.find<MusicServices>()
        .search(query, filter: 'featured_playlists', limit: 5);
    final playlist = res.values
        .whereType<List>()
        .expand((l) => l)
        .whereType<Playlist>()
        .firstOrNull;
    if (playlist == null) return false;
    return playCollection(
        isAlbum: false, id: playlist.playlistId, title: playlist.title);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: RiffSpacing.chipRowTop),
      child: SizedBox(
        height: RiffSizes.chipRow,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.gutter),
          itemCount: homeStations.length,
          separatorBuilder: (_, __) => const SizedBox(width: RiffSpacing.sm),
          itemBuilder: (context, i) {
            final s = homeStations[i];
            return _StationChip(
              station: s,
              busy: _busy == s.key,
              onTap: () => _start(s),
            );
          },
        ),
      ),
    );
  }
}

class _StationChip extends StatelessWidget {
  const _StationChip(
      {required this.station, required this.busy, required this.onTap});
  final HomeStation station;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final riff = RiffColors.of(context);
    final label = station.key.tr;
    // §5.6: outlined pill; the "selected" look while the station starts.
    final accent = theme.colorScheme.primary;
    final fg = busy ? accent : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      label: '${'startStation'.tr}: $label',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          // 48dp touch target around a 32dp chip.
          child: SizedBox(
            height: RiffSizes.chipRow,
            child: Center(
              child: Container(
                height: RiffSizes.chipHeight,
                padding: const EdgeInsets.only(
                    left: RiffSpacing.xs,
                    top: RiffSpacing.xs,
                    right: RiffSpacing.md,
                    bottom: RiffSpacing.xs),
                decoration: ShapeDecoration(
                  color: busy ? riff.accentMuted : Colors.transparent,
                  shape: StadiumBorder(
                    side: BorderSide(
                        color: busy ? accent : theme.dividerColor, width: 0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: RiffSizes.chipIcon,
                      height: RiffSizes.chipIcon,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: station.colors,
                        ),
                      ),
                      child: busy
                          ? Padding(
                              padding: const EdgeInsets.all(RiffSpacing.xs),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: riff.onImage),
                            )
                          : Icon(station.icon,
                              color: riff.onImage, size: RiffSizes.chipGlyph),
                    ),
                    const SizedBox(width: RiffSpacing.sm),
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(color: fg),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
