import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_spacing.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';

/// Hold-and-slide seeking on the play button: a slide jumps in whole
/// [holdSeekStep]s (5 s steps, about 15 s per 45 dp).
const double holdSeekDpPerSecond = 3;
const int holdSeekStep = 5;

int holdSeekSeconds(double dx) =>
    (dx / holdSeekDpPerSecond / holdSeekStep).round() * holdSeekStep;

/// "−0:15", "+1:05", "0:00".
String holdSeekLabel(int seconds) {
  final sign = seconds < 0
      ? '−'
      : seconds > 0
          ? '+'
          : '';
  final s = seconds.abs();
  return '$sign${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A button that animates between a play and pause icon.
///
/// Filled secondary circle with a dark icon. Buffering never replaces
/// play/pause — a faint ring can appear, but the button stays tappable.
class AnimatedPlayButton extends StatefulWidget {
  /// size of the icon.
  final double iconSize;

  /// Outer diameter of the filled circle (default ~64).
  final double size;

  /// Circle fill; defaults to the accent. The mini player passes
  /// `Colors.transparent` for a bare glyph.
  final Color? color;

  /// Glyph (and buffering ring) colour; defaults to the dark on-accent.
  final Color? iconColor;

  /// Full players: hold the button and slide left to jump back, right to
  /// jump forward; a bubble above it shows how far.
  final bool holdToSeek;

  const AnimatedPlayButton({
    super.key,
    this.iconSize = 32.0,
    this.size = 64.0,
    this.color,
    this.iconColor,
    this.holdToSeek = false,
  });

  @override
  State<AnimatedPlayButton> createState() => _AnimatedPlayButtonState();
}

class _AnimatedPlayButtonState extends State<AnimatedPlayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// Seconds the current hold-and-slide would jump; null when not holding.
  int? _seek;

  void _holdStart(LongPressStartDetails _) {
    HapticFeedback.mediumImpact();
    setState(() => _seek = 0);
  }

  void _holdMove(LongPressMoveUpdateDetails d) {
    final status = Get.find<PlayerController>().progressBarStatus.value;
    var seconds = holdSeekSeconds(d.offsetFromOrigin.dx);
    final back = -status.current.inSeconds;
    final ahead = (status.total - status.current).inSeconds;
    if (seconds < back) seconds = back;
    if (status.total > Duration.zero && seconds > ahead) seconds = ahead;
    if (seconds == _seek) return;
    HapticFeedback.selectionClick();
    setState(() => _seek = seconds);
  }

  void _holdEnd() {
    final seconds = _seek ?? 0;
    setState(() => _seek = null);
    if (seconds == 0) return;
    HapticFeedback.lightImpact();
    Get.find<PlayerController>().seekBy(Duration(seconds: seconds));
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? Theme.of(context).colorScheme.secondary;
    final glyph = widget.iconColor ?? RiffSurfaces.voidBlack;
    return GetX<PlayerController>(builder: (controller) {
      final buttonState = controller.buttonState.value;
      final isPlaying = buttonState == PlayButtonState.playing;
      final isLoading = buttonState == PlayButtonState.loading;

      if (isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }

      final button = Material(
        color: accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            isPlaying ? controller.pause() : controller.play();
          },
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _controller,
                    size: widget.iconSize,
                    color: glyph,
                  ),
                  if (isLoading)
                    SizedBox.square(
                      dimension: widget.size - 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: glyph.withOpacity(0.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!widget.holdToSeek) return button;
      final seek = _seek;
      return GestureDetector(
        onLongPressStart: _holdStart,
        onLongPressMoveUpdate: _holdMove,
        onLongPressEnd: (_) => _holdEnd(),
        onLongPressCancel: () => setState(() => _seek = null),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            button,
            if (seek != null)
              Positioned(
                bottom: widget.size + RiffSpacing.sm,
                child: IgnorePointer(child: _SeekBubble(seconds: seek)),
              ),
          ],
        ),
      );
    });
  }
}

/// "−0:15" over the play button while holding and sliding.
class _SeekBubble extends StatelessWidget {
  const _SeekBubble({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Material(
      color: RiffColors.of(context).surface2,
      shape: StadiumBorder(side: BorderSide(color: theme.dividerColor)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: RiffSpacing.md, vertical: RiffSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fast_rewind_rounded,
                size: RiffComponentSizes.trailingIcon,
                color: seconds < 0 ? theme.colorScheme.secondary : muted),
            const SizedBox(width: RiffSpacing.sm),
            Text(holdSeekLabel(seconds), style: theme.textTheme.labelMedium),
            const SizedBox(width: RiffSpacing.sm),
            Icon(Icons.fast_forward_rounded,
                size: RiffComponentSizes.trailingIcon,
                color: seconds > 0 ? theme.colorScheme.secondary : muted),
          ],
        ),
      ),
    );
  }
}
