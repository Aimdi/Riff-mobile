import 'package:flutter/material.dart';
import '/models/durationstate.dart';
import '/ui/theme/riff_tokens.dart';

class MiniPlayerProgressBar extends StatelessWidget {
  const MiniPlayerProgressBar(
      {super.key,
      required this.progressBarStatus,
      required this.progressBarColor});
  final ProgressBarState progressBarStatus;
  final Color progressBarColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
          MediaQuery.of(context).size.width, RiffComponentSizes.miniProgress),
      painter: ProgressBarPainter(
          current: progressBarStatus.current,
          total: progressBarStatus.total,
          progressBarColor: progressBarColor),
    );
  }
}

class ProgressBarPainter extends CustomPainter {
  ProgressBarPainter(
      {required this.current,
      required this.total,
      required this.progressBarColor});
  final Duration current;
  final Duration total;
  final Color progressBarColor;
  @override
  void paint(Canvas canvas, Size size) {
    // A flat 2-px accent line filling the track's height.
    const y = RiffComponentSizes.miniProgress / 2;
    const p1 = Offset(0, y);
    // Milliseconds, so the line creeps along with each position tick
    // instead of jumping once a second.
    final totalMs = total.inMilliseconds;
    final p2 = Offset(
        totalMs <= 0
            ? 0
            : size.width * (current.inMilliseconds / totalMs).clamp(0.0, 1.0),
        y);
    final paint = Paint()
      ..color = progressBarColor
      ..strokeWidth = RiffComponentSizes.miniProgress
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(p1, p2, paint);
  }

  @override
  bool shouldRepaint(covariant ProgressBarPainter oldDelegate) {
    // Repaints at most as often as the position is published (throttled
    // to 10 Hz), and not at all for a tick that didn't move it.
    return oldDelegate.current.inMilliseconds != current.inMilliseconds ||
        oldDelegate.total.inMilliseconds != total.inMilliseconds ||
        oldDelegate.progressBarColor != progressBarColor;
  }
}
