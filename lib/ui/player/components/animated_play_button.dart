import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';

/// A button that animates between a play and pause icon.
///
/// Filled secondary circle with a dark icon. Buffering never replaces
/// play/pause — a faint ring can appear, but the button stays tappable.
class AnimatedPlayButton extends StatefulWidget {
  /// size of the icon.
  final double iconSize;

  /// Outer diameter of the filled circle (default ~64).
  final double size;

  const AnimatedPlayButton({
    super.key,
    this.iconSize = 32.0,
    this.size = 64.0,
  });

  @override
  State<AnimatedPlayButton> createState() => _AnimatedPlayButtonState();
}

class _AnimatedPlayButtonState extends State<AnimatedPlayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

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
    final accent = Theme.of(context).colorScheme.secondary;
    return GetX<PlayerController>(builder: (controller) {
      final buttonState = controller.buttonState.value;
      final isPlaying = buttonState == PlayButtonState.playing;
      final isLoading = buttonState == PlayButtonState.loading;

      if (isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }

      return Material(
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
                    color: RiffSurfaces.voidBlack,
                  ),
                  if (isLoading)
                    SizedBox.square(
                      dimension: widget.size - 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: RiffSurfaces.voidBlack.withOpacity(0.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
