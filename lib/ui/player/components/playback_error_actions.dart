import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../player_controller.dart';

/// Retry the current stream or skip to the next queue item.
class PlaybackErrorActions extends StatelessWidget {
  const PlaybackErrorActions({
    super.key,
    this.compact = false,
    this.color,
  });

  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final style = TextButton.styleFrom(
      padding: compact ? const EdgeInsets.symmetric(horizontal: 6) : null,
      minimumSize: compact ? Size.zero : null,
      tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      visualDensity: compact ? VisualDensity.compact : null,
      foregroundColor: color,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: playerController.retryPlayback,
          style: style,
          child: Text('retry'.tr),
        ),
        TextButton(
          onPressed: playerController.skipFailedPlayback,
          style: style,
          child: const Text('Skip'),
        ),
      ],
    );
  }
}
