import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Asks before something that can't be taken back (Spotify and YouTube
/// Music confirm deleting a playlist). The confirming action is in the
/// danger colour; true only when the user confirmed.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
