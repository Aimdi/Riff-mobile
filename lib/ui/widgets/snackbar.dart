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

/// Where an Undo snackbar goes and the theme it is drawn in.
typedef UndoSnackbarTarget = ({
  ScaffoldMessengerState messenger,
  ThemeData theme,
});

/// The [UndoSnackbarTarget] for [context], looked up while it is still
/// mounted: the row or tile that asked (swiped away, unfollowed) is
/// usually gone by the time the change is done; the messenger isn't (it
/// sits above the app theme, so the theme is kept from here too). Without
/// a mounted [context], the app's.
UndoSnackbarTarget? undoSnackbarTarget(BuildContext? context) {
  final ctx = (context != null && context.mounted) ? context : Get.context;
  if (ctx == null) return null;
  final messenger = ScaffoldMessenger.maybeOf(ctx);
  return messenger == null
      ? null
      : (messenger: messenger, theme: Theme.of(ctx));
}

/// Shows [text] at [target] in place of the snackbar before it, with Undo
/// when [onUndo] is given. Null when there is nowhere to show it.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showUndoSnackbar(
    UndoSnackbarTarget? target, String text,
    {VoidCallback? onUndo}) {
  if (target == null || !target.messenger.mounted) return null;
  target.messenger.hideCurrentSnackBar();
  return target.messenger.showSnackBar(themedSnackbar(target.theme, text,
      actionLabel: onUndo == null ? null : 'undo'.tr, onAction: onUndo));
}

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
        VoidCallback? onAction}) =>
    themedSnackbar(Theme.of(context), text,
        bottom: top
            ? MediaQuery.of(context).size.height * 0.8
            : RiffSpacing.snackbarBottom,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction);

/// [snackbar] in a [theme] kept from earlier, [bottom] above the screen's
/// bottom edge.
SnackBar themedSnackbar(ThemeData theme, String text,
    {double bottom = RiffSpacing.snackbarBottom,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction}) {
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
        bottom: bottom, left: RiffSpacing.lg, right: RiffSpacing.lg),
    behavior: SnackBarBehavior.floating,
    duration: duration ??
        (hasAction ? snackbarActionDuration : const Duration(seconds: 1)),
    elevation: 0,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(RiffRadii.sm))),
  );
}
