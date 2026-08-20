import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '/utils/hive_boxes.dart';

/// Planned LIBFAV write for a like/unlike tap (same shape as Hive).
class FavouriteTogglePlan {
  const FavouriteTogglePlan({
    required this.adding,
    required this.songId,
    this.record,
  });

  final bool adding;
  final String songId;

  /// Hive value when [adding] is true (`MediaItemBuilder.toJson`).
  final Map<String, dynamic>? record;
}

FavouriteTogglePlan planFavouriteToggle(
  MediaItem song, {
  required bool currentlyFavourite,
}) {
  final adding = !currentlyFavourite;
  return FavouriteTogglePlan(
    adding: adding,
    songId: song.id,
    record: adding ? MediaItemBuilder.toJson(song) : null,
  );
}

/// Apply [plan] to an in-memory LIBFAV map (Hive box contract).
void applyFavouriteToggle(
  Map<dynamic, dynamic> libFav,
  FavouriteTogglePlan plan,
) {
  if (plan.adding) {
    libFav[plan.songId] = plan.record;
  } else {
    libFav.remove(plan.songId);
  }
}

bool songIsInLibFav(String songId) => HiveBoxes.favContains(songId);

/// Same window as [FavoriteHeartButton.toggleDebounce].
const Duration songRowHeartDebounce = Duration(milliseconds: 400);

bool shouldIgnoreHeartToggle(DateTime? lastToggle, DateTime now) =>
    lastToggle != null && now.difference(lastToggle) < songRowHeartDebounce;

/// Compact row heart — likes [song], not only the now-playing track.
class SongRowHeartButton extends StatefulWidget {
  const SongRowHeartButton({
    super.key,
    required this.song,
    this.iconSize = 20,
    this.color,
  });

  final MediaItem song;
  final double iconSize;
  final Color? color;

  @override
  State<SongRowHeartButton> createState() => _SongRowHeartButtonState();
}

class _SongRowHeartButtonState extends State<SongRowHeartButton> {
  late bool _fav;
  DateTime? _lastToggle;

  @override
  void initState() {
    super.initState();
    _fav = songIsInLibFav(widget.song.id);
  }

  @override
  void didUpdateWidget(covariant SongRowHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _fav = songIsInLibFav(widget.song.id);
    }
  }

  void _toggle(PlayerController player, {required bool isCurrent}) {
    final now = DateTime.now();
    if (shouldIgnoreHeartToggle(_lastToggle, now)) return;
    _lastToggle = now;
    if (isCurrent) {
      player.toggleFavourite();
      return;
    }
    final next = !_fav;
    setState(() => _fav = next);
    player.toggleFavouriteFor(widget.song, adding: next);
  }

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    return Obx(() {
      final isCurrent = player.currentSong.value?.id == widget.song.id;
      final fav = isCurrent ? player.isCurrentSongFav.isTrue : _fav;
      final scheme = Theme.of(context).colorScheme;
      return IconButton(
        tooltip: 'favorites'.tr,
        iconSize: widget.iconSize,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        splashRadius: 18,
        onPressed: () => _toggle(player, isCurrent: isCurrent),
        icon: Icon(
          fav ? Icons.favorite : Icons.favorite_border,
          color: fav ? scheme.secondary : widget.color,
          size: widget.iconSize,
        ),
      );
    });
  }
}
