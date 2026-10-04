// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/play_queue_order.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/player/player_controller.dart';

enum SanckBarSize { BIG, MEDIUM, SMALL }

/// Play / save failed — tell the user instead of staying silent.
/// Skips when [notifyPlayError] already snacked the stream failure.
void snackOperationFailed([BuildContext? context]) {
  if (Get.isRegistered<PlayerController>()) {
    final err = Get.find<PlayerController>().playbackError.value;
    if (!shouldSnackGenericPlayFailed(err)) return;
  }
  final ctx = context ?? Get.context;
  if (ctx == null || !ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    snackbar(ctx, 'operationFailed'.tr, size: SanckBarSize.MEDIUM),
  );
}

/// The app's snackbar (§5.12): floating, 16dp side margins, radius 8,
/// accent fill, 15/600 text in the on-accent colour. It sits above the
/// mini player, or near the top when [top] is set. [size] is kept for
/// existing callers; the width now follows the 16dp margins.
SnackBar snackbar(BuildContext context, String text,
    {SanckBarSize size = SanckBarSize.MEDIUM,
    Duration duration = const Duration(seconds: 1),
    bool top = false}) {
  final theme = Theme.of(context);
  final onAccent = theme.colorScheme.onSecondary;
  return SnackBar(
    backgroundColor: theme.colorScheme.secondary,
    content: Center(
      child: Text(
        text,
        style: (theme.snackBarTheme.contentTextStyle ??
                theme.textTheme.labelMedium)
            ?.copyWith(color: onAccent),
      ),
    ),
    margin: EdgeInsets.only(
        bottom: top
            ? MediaQuery.of(context).size.height * 0.8
            : RiffSpacing.snackbarBottom,
        left: RiffSpacing.lg,
        right: RiffSpacing.lg),
    behavior: SnackBarBehavior.floating,
    duration: duration,
    elevation: 0,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(RiffRadii.sm))),
  );
}
