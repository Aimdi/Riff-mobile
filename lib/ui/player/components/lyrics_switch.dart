import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:toggle_switch/toggle_switch.dart';

import '../player_controller.dart';

class LyricsSwitch extends StatelessWidget {
  const LyricsSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.secondary;
    return Obx(
      () => playerController.showLyricsflag.value
          ? Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: ToggleSwitch(
                minWidth: 90.0,
                cornerRadius: 20.0,
                activeBgColors: [
                  [accent],
                  [accent],
                ],
                activeFgColor: scheme.onSecondary,
                inactiveBgColor: scheme.surfaceContainerLow,
                inactiveFgColor: scheme.onSurfaceVariant,
                initialLabelIndex: playerController.lyricsMode.value,
                totalSwitches: 2,
                labels: ['synced'.tr, 'plain'.tr],
                radiusStyle: true,
                onToggle: playerController.changeLyricsMode,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
