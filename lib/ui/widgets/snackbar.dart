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

/// How long a snackbar with an action (Undo) stays, so there is time to
/// reach it (Material's minimum for actions).
const Duration snackbarActionDuration = Duration(seconds: 4);

/// The app's snackbar (§5.12): floating, 16dp side margins, radius 8,
/// accent fill, 15/600 text in the on-accent colour. It sits above the
/// mini player, or near the top when [top] is set. [size] is kept for
/// existing callers; the width now follows the 16dp margins. With
/// [actionLabel] and [onAction] it gets a button (e.g. Undo), the text
/// moves to the start and it stays [snackbarActionDuration] by default.
SnackBar snackbar(BuildContext context, String text,
    {SanckBarSize size = SanckBarSize.MEDIUM,
    Duration? duration,
    bool top = false,
    String? actionLabel,
    VoidCallback? onAction}) {
  final theme = Theme.of(context);
  final onAccent = theme.colorScheme.onSecondary;
  final hasAction = actionLabel != null && onAction != null;
  final label = Text(
    text,
    style: (theme.snackBarTheme.contentTextStyle ??
            theme.textTheme.labelMedium)
        ?.copyWith(color: onAccent),
  );
  return SnackBar(
    backgroundColor: theme.colorScheme.secondary,
    content: hasAction ? label : Center(child: label),
    action: hasAction
        ? SnackBarAction(
            label: actionLabel,
            textColor: onAccent,
            onPressed: onAction,
          )
        : null,
    margin: EdgeInsets.only(
        bottom: top
            ? MediaQuery.of(context).size.height * 0.8
            : RiffSpacing.snackbarBottom,
        left: RiffSpacing.lg,
        right: RiffSpacing.lg),
    behavior: SnackBarBehavior.floating,
    duration: duration ??
        (hasAction ? snackbarActionDuration : const Duration(seconds: 1)),
    elevation: 0,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(RiffRadii.sm))),
  );
}
