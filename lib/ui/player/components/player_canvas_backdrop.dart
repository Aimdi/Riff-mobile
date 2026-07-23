import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Subtle ambient motion behind album art (Echo Canvas–lite).
///
/// Slow drifting gradient blobs — no network, low GPU cost.
class PlayerCanvasBackdrop extends StatefulWidget {
  const PlayerCanvasBackdrop({super.key});

  @override
  State<PlayerCanvasBackdrop> createState() => _PlayerCanvasBackdropState();
}

class _PlayerCanvasBackdropState extends State<PlayerCanvasBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      -0.6 + t * 0.4,
                      -0.5 + math.sin(t * math.pi) * 0.3,
                    ),
                    radius: 1.1,
                    colors: [
                      accent.withOpacity(0.28),
                      bg.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      0.7 - t * 0.35,
                      0.6 - math.cos(t * math.pi) * 0.25,
                    ),
                    radius: 0.95,
                    colors: [
                      accent.withOpacity(0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Soft vignette so art/lyrics stay readable.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      bg.withOpacity(0.15),
                      Colors.transparent,
                      bg.withOpacity(0.55),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
