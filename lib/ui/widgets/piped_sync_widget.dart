import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/utils/helper.dart';

import '../screens/Library/library_controller.dart';
import 'riff_motion.dart';
import 'snackbar.dart';

class PipedSyncWidget extends StatelessWidget {
  const PipedSyncWidget({super.key, required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final librplstCntrller = Get.find<LibraryPlaylistsController>();
    return Padding(
      padding: padding,
      child: RotationTransition(
        turns: Tween(begin: 0.0, end: 1.0).animate(librplstCntrller.controller),
        child: IconButton(
            splashRadius: 20,
            iconSize: 20,
            visualDensity: const VisualDensity(vertical: -4),
            tooltip: 'syncPipedPlaylists'.tr,
            icon: const Icon(
              Icons.sync,
            ), // <-- Icon
            onPressed: () async {
              final spin = librplstCntrller.controller;
              try {
                // Remove animations: no spinning (a repeat isn't shortened
                // as one-shot animations are).
                if (!reduceMotion(context)) spin.repeat();
                final ok = await librplstCntrller.syncPipedPlaylist();
                ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                    Get.context!,
                    ok ? "pipedplstSyncAlert".tr : "errorOccuredAlert".tr,
                    size: SanckBarSize.MEDIUM));
              } catch (e) {
                ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                    Get.context!, "errorOccuredAlert".tr,
                    size: SanckBarSize.BIG));
                printERROR(e);
              } finally {
                // Also after a failed sync: the icon used to keep spinning
                // (and ticking every frame) until the app was restarted.
                spin.stop();
                // It finishes its half turn at the same speed rather than
                // snapping back (the sync glyph looks the same every half
                // turn), then rests at 0.
                final rest = spin.value <= 0.5 ? 0.5 : 1.0;
                if (spin.value > 0) {
                  spin
                      .animateTo(rest,
                          duration: spin.duration! * (rest - spin.value))
                      .whenComplete(spin.reset);
                }
              }
            }),
      ),
    );
  }
}
