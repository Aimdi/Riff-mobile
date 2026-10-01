import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/music_service.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/snackbar.dart';
import 'home_layout.dart';

/// One mood under the greeting: a label and the YouTube Music search that
/// finds a featured playlist for it.
class HomeMood {
  const HomeMood(this.key, this.icon, this.query);
  final String key;
  final IconData icon;
  final String query;
}

const homeMoods = [
  HomeMood('moodRelax', Icons.spa_outlined, 'relax chill mix'),
  HomeMood('moodSleep', Icons.bedtime_outlined, 'sleep'),
  HomeMood('moodFocus', Icons.center_focus_strong_outlined, 'focus'),
  HomeMood('moodEnergy', Icons.bolt_outlined, 'energy workout'),
  HomeMood('moodSad', Icons.water_drop_outlined, 'sad songs'),
  HomeMood('moodParty', Icons.celebration_outlined, 'party hits'),
];

/// Mood chips: one tap plays a featured playlist for that mood.
class HomeMoodChips extends StatefulWidget {
  const HomeMoodChips({super.key});

  @override
  State<HomeMoodChips> createState() => _HomeMoodChipsState();
}

class _HomeMoodChipsState extends State<HomeMoodChips> {
  String? _busy;

  Future<void> _play(HomeMood mood) async {
    if (_busy != null) return;
    setState(() => _busy = mood.key);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await Get.find<MusicServices>()
          .search(mood.query, filter: 'featured_playlists', limit: 5);
      final playlist = res.values
          .whereType<List>()
          .expand((l) => l)
          .whereType<Playlist>()
          .firstOrNull;
      if (!mounted) return;
      final ok = playlist != null &&
          await playCollection(
              isAlbum: false, id: playlist.playlistId, title: playlist.title);
      if (!ok && mounted) {
        messenger.showSnackBar(
            snackbar(context, 'mixEmpty'.tr, size: SanckBarSize.MEDIUM));
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          snackbar(context, 'networkError'.tr, size: SanckBarSize.MEDIUM));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color;
    final accent = theme.colorScheme.secondary;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
        itemCount: homeMoods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final mood = homeMoods[i];
          final busy = _busy == mood.key;
          return Material(
            color: homeTileColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: homeTileBorder(context),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _play(mood),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    busy
                        ? SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: accent))
                        : Icon(mood.icon, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Text(mood.key.tr,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: fg)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
