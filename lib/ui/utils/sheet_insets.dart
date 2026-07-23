import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';

/// Bottom padding for modal sheets.
///
/// When [liftAboveMiniPlayer] is true (default), also clears the collapsed
/// mini-player height — needed for sheets opened from the nested navigator,
/// which paint *under* the SlidingUpPanel header.
///
/// Prefer `useRootNavigator: true` on the sheet itself; then call with
/// `liftAboveMiniPlayer: false` so you only keep the system safe area.
double sheetBottomInset(
  BuildContext context, {
  bool liftAboveMiniPlayer = true,
}) {
  final safe = MediaQuery.paddingOf(context).bottom;
  if (!liftAboveMiniPlayer) return safe;
  if (!Get.isRegistered<PlayerController>()) return safe;

  final player = Get.find<PlayerController>();
  if (player.currentSong.value == null) return safe;
  if (player.isPlayerPanelOpen.value) return safe;

  final mini = player.playerPanelMinHeight.value;
  if (mini <= 0) return safe;
  return safe + mini;
}
