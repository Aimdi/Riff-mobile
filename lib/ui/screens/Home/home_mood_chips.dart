import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/music_service.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/snackbar.dart';
import 'home_layout.dart';
import 'home_screen_controller.dart';

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

/// Chip row under the greeting: YouTube Music's home chips, which filter
/// the feed, or (when YouTube sent none) Riff's moods, which play a
/// featured playlist.
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
    final home = Get.find<HomeScreenController>();
    return Obx(() {
      final chips = home.homeChips.toList();
      final selected = home.selectedChip.value;
      final loading = home.chipLoading.value;
      if (chips.isNotEmpty) {
        // YouTube Music's own chips: tap filters the whole feed, tap again
        // goes back (Echo Music's chip row).
        return _row(context, [
          for (final chip in chips)
            _chip(
              context,
              label: chip.title,
              selected: chip == selected,
              busy: loading && chip == selected,
              onTap: () => home.selectChip(chip),
            ),
        ]);
      }
      // Offline / no chips from YouTube: Riff's moods, which play a
      // featured playlist instead.
      return _row(context, [
        for (final mood in homeMoods)
          _chip(
            context,
            label: mood.key.tr,
            icon: mood.icon,
            busy: _busy == mood.key,
            onTap: () => _play(mood),
          ),
      ]);
    });
  }

  Widget _row(BuildContext context, List<Widget> children) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => children[i],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    bool selected = false,
    bool busy = false,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final fg = selected ? Colors.black : theme.textTheme.titleMedium?.color;
    return Material(
      color: selected ? accent : homeTileColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected ? BorderSide.none : homeTileBorder(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (busy) ...[
                SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: selected ? Colors.black : accent)),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
