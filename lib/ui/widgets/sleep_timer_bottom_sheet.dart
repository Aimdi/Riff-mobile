import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/play_queue_order.dart';
import '/ui/player/player_controller.dart';
import 'snackbar.dart';

/// Opens the sleep-timer sheet from the full player, mini player, or song menu.
Future<void> showSleepTimerSheet(BuildContext? context) async {
  final sheetContext = context ?? Get.context;
  if (sheetContext == null) return;
  await showModalBottomSheet<void>(
    constraints: const BoxConstraints(maxWidth: 500),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
    ),
    isScrollControlled: true,
    context: sheetContext,
    barrierColor: Colors.transparent.withAlpha(100),
    builder: (context) => const SleepTimerBottomSheet(),
  );
}

class SleepTimerBottomSheet extends StatelessWidget {
  const SleepTimerBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Padding(
      padding: EdgeInsets.only(bottom: Get.mediaQuery.padding.bottom),
      child: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer),
              title: Text("sleepTimer".tr),
            ),
            const Divider(),
            if (playerController.isSleepTimerActive.isTrue)
              SizedBox(
                height: 90,
                child: Container(
                  width: 180,
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(20)),
                  child: Align(
                    alignment: Alignment.center,
                    child: Obx(() {
                      final leftDurationInSec =
                          playerController.timerDurationLeft.value;
                      final hrs = (leftDurationInSec ~/ 3600)
                          .toString()
                          .padLeft(2, '0');
                      final min = ((leftDurationInSec % 3600) ~/ 60)
                          .toString()
                          .padLeft(2, '0');
                      final sec = ((leftDurationInSec % 3600) % 60)
                          .toString()
                          .padLeft(2, '0');

                      return Text(
                        "$hrs:$min:$sec",
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge!
                            .copyWith(fontSize: 35),
                      );
                    }),
                  ),
                ),
              ),
            if (playerController.isSleepTimerActive.isFalse)
              Column(
                children: getTimeListWidget(context),
              ),
            if (playerController.isSleepTimerActive.isTrue)
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0, top: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (playerController.isSleepEndOfSongActive.isFalse)
                      OutlinedButton(
                          onPressed: playerController.addFiveMinutes,
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).textTheme.titleMedium!.color!,
                            side: BorderSide(
                              color: Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .color!,
                            ),
                          ),
                          child: Text("add5Minutes".tr)),
                    OutlinedButton(
                        onPressed: () {
                          playerController.cancelSleepTimer();
                          Navigator.of(context).pop();
                          final ctx = Get.context;
                          if (ctx == null || !ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
                              ctx, "cancelTimerAlert".tr,
                              size: SanckBarSize.BIG));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).textTheme.titleMedium!.color!,
                          side: BorderSide(
                            color:
                                Theme.of(context).textTheme.titleMedium!.color!,
                          ),
                        ),
                        child: Text("cancelTimer".tr))
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> getTimeListWidget(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final List<Widget> widgets = [];
    widgets.addAll([5, 10, 15, 30, 45, 60]
        .map((dur) => ListTile(
              onTap: () {
                final ok = playerController.startSleepTimer(dur);
                Navigator.of(context).pop();
                final ctx = Get.context;
                if (ctx == null || !ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
                    ctx,
                    ok ? "sleepTimeSetAlert".tr : "operationFailed".tr,
                    size: SanckBarSize.BIG));
              },
              leading: Padding(
                padding: const EdgeInsets.only(left: 10.0),
                child: Text(
                  "$dur ${'minutes'.tr}",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ))
        .toList());
    widgets.add(ListTile(
      onTap: () {
        Navigator.of(context).pop();
        playerController.sleepEndOfSong();
      },
      leading: Padding(
        padding: const EdgeInsets.only(left: 10.0),
        child: Text(
          sleepEndLabelKey(
                  longForm: playerController.usesLongFormTransport)
              .tr,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ));
    return widgets;
  }
}
