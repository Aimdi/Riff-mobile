import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_service.dart';
import '/ui/widgets/add_to_playlist.dart';

/// Heart control: tap toggles Likes/Favorites; a short hold opens Add to playlist.
///
/// Hold window is intentionally between a tap and Flutter's default long-press
/// (~500ms) so playlist options appear without feeling sluggish.
class FavoriteHeartButton extends StatefulWidget {
  const FavoriteHeartButton({
    super.key,
    required this.isFav,
    required this.onToggleFav,
    required this.song,
    this.iconSize,
    this.color,
    this.splashRadius,
    this.visualDensity,
    this.constraints,
    this.padding,
  });

  /// Reactive fav flag (e.g. `playerController.isCurrentSongFav`).
  final RxBool isFav;
  final VoidCallback onToggleFav;

  /// Song to add when the medium-press playlist picker opens.
  final MediaItem? Function() song;

  final double? iconSize;
  final Color? color;
  final double? splashRadius;
  final VisualDensity? visualDensity;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;

  /// Hold duration that opens the playlist picker (not tap, not a long hold).
  static const Duration mediumPress = Duration(milliseconds: 350);

  @override
  State<FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<FavoriteHeartButton> {
  Timer? _holdTimer;
  bool _openedPlaylist = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    _openedPlaylist = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(FavoriteHeartButton.mediumPress, () {
      if (!mounted) return;
      _openedPlaylist = true;
      HapticFeedback.selectionClick();
      _openAddToPlaylist();
    });
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _onPressed() {
    _cancelHoldTimer();
    // Finger-up after a medium hold still delivers IconButton.onPressed —
    // skip the fav toggle in that case.
    if (_openedPlaylist) {
      _openedPlaylist = false;
      return;
    }
    widget.onToggleFav();
  }

  void _openAddToPlaylist() {
    final song = widget.song();
    if (song == null || !mounted) return;
    showDialog(
      context: context,
      builder: (context) => AddToPlaylist([song]),
    ).whenComplete(() {
      if (Get.isRegistered<DiscoveryService>()) {
        Get.find<DiscoveryService>().onPlaylistAdd(song);
      }
      if (Get.isRegistered<AddToPlaylistController>()) {
        Get.delete<AddToPlaylistController>();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).textTheme.titleMedium!.color;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerCancel: (_) => _cancelHoldTimer(),
      child: IconButton(
        tooltip: 'favHeartHint'.tr,
        iconSize: widget.iconSize,
        splashRadius: widget.splashRadius,
        visualDensity: widget.visualDensity,
        constraints: widget.constraints,
        padding: widget.padding,
        onPressed: _onPressed,
        icon: Obx(
          () => Icon(
            widget.isFav.isFalse ? Icons.favorite_border : Icons.favorite,
            color: color,
            size: widget.iconSize,
          ),
        ),
      ),
    );
  }
}
