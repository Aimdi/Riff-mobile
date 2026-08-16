import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

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

  /// Ignore a second tap that would immediately unlike.
  static const Duration toggleDebounce = Duration(milliseconds: 400);

  @override
  State<FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<FavoriteHeartButton> {
  Timer? _holdTimer;
  bool _openedPlaylist = false;
  DateTime? _lastToggle;

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
    final now = DateTime.now();
    if (_lastToggle != null &&
        now.difference(_lastToggle!) < FavoriteHeartButton.toggleDebounce) {
      return;
    }
    _lastToggle = now;
    widget.onToggleFav();
  }

  void _openAddToPlaylist() {
    final song = widget.song();
    if (song == null || !mounted) return;
    showAddToPlaylistSheet(context, [song]);
  }

  @override
  Widget build(BuildContext context) {
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
          () {
            final fav = widget.isFav.isTrue;
            final scheme = Theme.of(context).colorScheme;
            final filled = scheme.secondary;
            final muted = (widget.color ?? scheme.onSurface).withOpacity(0.45);
            return Icon(
              fav ? Icons.favorite : Icons.favorite_border,
              color: fav ? filled : muted,
              size: widget.iconSize,
            );
          },
        ),
      ),
    );
  }
}
