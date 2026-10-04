import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/play_queue_order.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/theme/riff_spacing.dart';
import 'riff_sheet.dart';
import 'snackbar.dart';

/// Opens the sleep-timer sheet from the full player, mini player, or song menu.
Future<void> showSleepTimerSheet(BuildContext? context) async {
  final sheetContext = context ?? Get.context;
  if (sheetContext == null) return;
  await showModalBottomSheet<void>(
    constraints: const BoxConstraints(maxWidth: 500),
    shape: riffSheetShape,
    isScrollControlled: true,
    context: sheetContext,
    builder: (context) => const SleepTimerBottomSheet(),
  );
}

class SleepTimerBottomSheet extends StatelessWidget {
  const SleepTimerBottomSheet({super.key});

  static String _clock(int secs) {
    final h = secs ~/ 3600;
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _done(BuildContext context, String message) {
    Navigator.of(context).pop();
    final ctx = Get.context;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx)
        .showSnackBar(snackbar(ctx, message, size: SanckBarSize.BIG));
  }

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(
          bottom: Get.mediaQuery.padding.bottom + RiffSpacing.md),
      child: Obx(() {
        final active = playerController.isSleepTimerActive.isTrue;
        final endOfChapter = playerController.isSleepEndOfChapterActive.isTrue;
        final endOfSong =
            playerController.isSleepEndOfSongActive.isTrue || endOfChapter;
        final left = playerController.timerDurationLeft.value;
        final endLabel =
            sleepEndLabelKey(longForm: playerController.usesLongFormTransport)
                .tr;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('sleepTimer'.tr,
                trailing: Icon(Icons.bedtime_rounded,
                    size: RiffComponentSizes.sheetIcon, color: fg)),
            if (active) ...[
              const SizedBox(height: RiffSpacing.sm),
              Center(
                child: Text(
                  endOfChapter
                      ? 'endOfThisChapter'.tr
                      : endOfSong
                          ? endLabel
                          : _clock(left),
                  textAlign: TextAlign.center,
                  style: (endOfSong
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.displayLarge)
                      ?.copyWith(
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: RiffSpacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.lg),
                child: Row(
                  children: [
                    if (!endOfSong) ...[
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: playerController.addFiveMinutes,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  RiffComponentSizes.button)),
                          child: Text('add5Minutes'.tr),
                        ),
                      ),
                      const SizedBox(width: RiffSpacing.sm),
                    ],
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          playerController.cancelSleepTimer();
                          _done(context, 'cancelTimerAlert'.tr);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize:
                              const Size.fromHeight(RiffComponentSizes.button),
                        ),
                        child: Text('cancelTimer'.tr),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(
                    left: RiffSpacing.lg,
                    top: RiffSpacing.sm,
                    right: RiffSpacing.lg,
                    bottom: RiffSpacing.md),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: RiffSpacing.sm,
                  crossAxisSpacing: RiffSpacing.sm,
                  childAspectRatio: 2.4,
                  children: [
                    for (final dur in const [5, 10, 15, 30, 45, 60])
                      _DurationTile(
                        minutes: dur,
                        onTap: () {
                          final ok = playerController.startSleepTimer(dur);
                          _done(
                              context,
                              ok
                                  ? 'sleepTimeSetAlert'.tr
                                  : 'operationFailed'.tr);
                        },
                      ),
                  ],
                ),
              ),
              RiffSheetTile(
                icon: Icons.music_off_outlined,
                title: endLabel,
                onTap: () {
                  Navigator.of(context).pop();
                  playerController.sleepEndOfSong();
                },
              ),
              // Podcast episodes with chapters can also stop at the end of
              // the chapter playing now.
              if (playerController.isCurrentSongPodcast &&
                  playerController.chapters.isNotEmpty)
                RiffSheetTile(
                  icon: Icons.bookmark_border_rounded,
                  title: 'endOfThisChapter'.tr,
                  onTap: () {
                    Navigator.of(context).pop();
                    playerController.sleepEndOfChapter();
                  },
                ),
              if (playerController.isCurrentSongPodcast)
                Padding(
                  padding: const EdgeInsets.only(
                      left: RiffSpacing.lg,
                      top: RiffSpacing.xs,
                      right: RiffSpacing.lg),
                  child: Text('podcastSleepFadeNote'.tr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
          ],
        );
      }),
    );
  }
}

/// "15 min" tile in the duration grid.
class _DurationTile extends StatelessWidget {
  const _DurationTile({required this.minutes, required this.onTap});
  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      // One step above the sheet's surface1, flat, radius 8.
      color: RiffColors.of(context).surface2,
      borderRadius: BorderRadius.circular(RiffRadii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '$minutes',
                  style: text.titleLarge?.copyWith(color: scheme.onSurface)),
              TextSpan(
                  text: ' ${'minShort'.tr}',
                  style: text.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}
