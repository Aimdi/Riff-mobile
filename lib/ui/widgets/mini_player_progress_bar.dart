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
    final p2 = Offset(
        total.inSeconds == 0
            ? 0
            : size.width * (current.inSeconds / total.inSeconds),
        y);
    final paint = Paint()
      ..color = progressBarColor
      ..strokeWidth = RiffComponentSizes.miniProgress
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(p1, p2, paint);
  }

  @override
  bool shouldRepaint(covariant ProgressBarPainter oldDelegate) {
    // paint() only uses whole seconds, so sub-second ticks (10 Hz) are
    // visually identical — don't repaint for them.
    return oldDelegate.current.inSeconds != current.inSeconds ||
        oldDelegate.total.inSeconds != total.inSeconds ||
        oldDelegate.progressBarColor != progressBarColor;
  }
}
