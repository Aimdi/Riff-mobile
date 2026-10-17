import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/services/lyrics_timing.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/riff_sheet.dart';
import '../player_controller.dart';

/// ⋮ › Lyrics timing, for the song playing.
Future<void> showLyricsTimingSheet(BuildContext? context) async {
  final song = Get.find<PlayerController>().currentSong.value;
  if (context == null || !context.mounted || song == null) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    constraints: const BoxConstraints(maxWidth: 500),
    shape: riffSheetShape,
    builder: (_) => LyricsTimingSheet(songId: song.id),
  );
}

/// How far a song's lyrics are moved: "As timed", "0.5 s later", …
String lyricsTimingLabel(int delayMs) => delayMs == 0
    ? 'lyricsTimingAsIs'.tr
    : (delayMs > 0 ? 'lyricsTimingLater' : 'lyricsTimingEarlier')
        .trParams({'s': lyricsDelaySeconds(delayMs)});

/// Earlier / Later for a song's synced lyrics, half a second a tap, with
/// how far they're moved in between, and Reset. Small, so the lyrics stay
/// in view above it while you set them.
class LyricsTimingSheet extends StatelessWidget {
  const LyricsTimingSheet({super.key, required this.songId});

  final String songId;

  void _nudge(int steps) {
    HapticFeedback.selectionClick();
    LyricsTiming.nudge(songId, steps);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Obx(() {
        final delay = LyricsTiming.delayMs(songId);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('lyricsTiming'.tr, subtitle: 'lyricsTimingDes'.tr),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: RiffSpacing.lg, vertical: RiffSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _nudge(-1),
                      icon: const Icon(Icons.fast_rewind_rounded),
                      label: Text('lyricsEarlier'.tr),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      lyricsTimingLabel(delay),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _nudge(1),
                      icon: const Icon(Icons.fast_forward_rounded),
                      label: Text('lyricsLater'.tr),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.lg,
                  right: RiffSpacing.lg,
                  bottom: RiffSpacing.md),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: delay == 0
                      ? null
                      : () => LyricsTiming.setDelay(songId, 0),
                  child: Text('reset'.tr),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
