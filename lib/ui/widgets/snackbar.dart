// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/play_queue_order.dart';
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

SnackBar snackbar(BuildContext context, String text,
    {SanckBarSize size = SanckBarSize.MEDIUM,
    Duration duration = const Duration(seconds: 1),
    bool top = false}) {
  final scrWidth = MediaQuery.of(context).size.width;
  final hrMargin = size == SanckBarSize.BIG
      ? (scrWidth - 300) / 2
      : size == SanckBarSize.MEDIUM
          ? (scrWidth - 200) / 2
          : (scrWidth - 100) / 2;
  return SnackBar(
    backgroundColor: Theme.of(context).colorScheme.secondary,
    content: Center(
      child: Text(
        text,
        style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black),
      ),
    ),
    //width: width,

    margin: EdgeInsets.only(
        bottom: top ? MediaQuery.of(context).size.height * 0.8 : 100,
        left: hrMargin,
        right: hrMargin),
    behavior: SnackBarBehavior.floating,
    duration: duration,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  );
}
