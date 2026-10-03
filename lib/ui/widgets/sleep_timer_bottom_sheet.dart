import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/play_queue_order.dart';
import '/ui/player/player_controller.dart';
import '../screens/Home/home_layout.dart';
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';
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
    barrierColor: Colors.transparent.withAlpha(100),
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
    final fg = theme.textTheme.titleMedium?.color ?? RiffSurfaces.textPrimary;
    final accent = theme.colorScheme.secondary;
    return Padding(
      padding: EdgeInsets.only(bottom: Get.mediaQuery.padding.bottom + 12),
      child: Obx(() {
        final active = playerController.isSleepTimerActive.isTrue;
        final endOfChapter =
            playerController.isSleepEndOfChapterActive.isTrue;
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
                trailing: Icon(Icons.bedtime_rounded, color: accent)),
            if (active) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  endOfChapter
                      ? 'endOfThisChapter'.tr
                      : endOfSong
                          ? endLabel
                          : _clock(left),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: endOfSong ? 22 : 52,
                    fontWeight: FontWeight.w800,
                    letterSpacing: endOfSong ? 0 : -1,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (!endOfSong) ...[
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: playerController.addFiveMinutes,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48)),
                          child: Text('add5Minutes'.tr,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          playerController.cancelSleepTimer();
                          _done(context, 'cancelTimerAlert'.tr);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: fg,
                          side: BorderSide(color: fg.withOpacity(0.4)),
                        ),
                        child: Text('cancelTimer'.tr,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                  children: [
                    for (final dur in const [5, 10, 15, 30, 45, 60])
                      _DurationTile(
                        minutes: dur,
                        onTap: () {
                          final ok = playerController.startSleepTimer(dur);
                          _done(context,
                              ok ? 'sleepTimeSetAlert'.tr : 'operationFailed'.tr);
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
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text('podcastSleepFadeNote'.tr,
                      style: homeCardSubtitleStyle(context)),
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
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        RiffSurfaces.textPrimary;
    return Material(
      color: homeTileColor(context),
      borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '$minutes',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
              TextSpan(
                  text: ' ${'minShort'.tr}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg.withOpacity(0.7))),
            ]),
          ),
        ),
      ),
    );
  }
}
