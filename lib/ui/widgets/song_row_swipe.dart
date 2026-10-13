import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// The song row's right-hand swipe (drag it left): a short swipe opens
/// "Add to queue" and "Play next"; a swipe all the way across adds the
/// song to the queue straight away and springs back, like Spotify.
ActionPane songRowQueuePane({
  required Color background,
  required Color foreground,
  required VoidCallback onEnqueue,
  required VoidCallback onPlayNext,
}) {
  return ActionPane(
    motion: const DrawerMotion(),
    // Past the buttons (half the row) to three quarters: queue it. The row
    // isn't removed, it slides back.
    dismissible: DismissiblePane(
      closeOnCancel: true,
      confirmDismiss: () async {
        HapticFeedback.lightImpact();
        onEnqueue();
        return false;
      },
      onDismissed: () {},
    ),
    children: [
      SlidableAction(
        onPressed: (_) => onEnqueue(),
        backgroundColor: background,
        foregroundColor: foreground,
        icon: Icons.merge,
      ),
      SlidableAction(
        onPressed: (_) => onPlayNext(),
        backgroundColor: background,
        foregroundColor: foreground,
        icon: Icons.next_plan_outlined,
      ),
    ],
  );
}
