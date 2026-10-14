import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/auto_sleep_timer.dart';
import '/services/sleep_shake.dart';
import '/ui/player/play_queue_order.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/theme/riff_spacing.dart';
import 'cust_switch.dart';
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
                          playerController.turnOffSleepTimer();
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
              // A timed timer: shake to start it over (Pocket Casts,
              // AntennaPod).
              if (!endOfSong && GetPlatform.isAndroid) ...[
                const SizedBox(height: RiffSpacing.sm),
                RiffSheetTile(
                  icon: Icons.vibration_rounded,
                  title: 'shakeToRestart'.tr,
                  subtitle: 'shakeToRestartDes'.tr,
                  onTap: () =>
                      SleepShake.setEnabled(SleepShake.enabled.isFalse),
                  trailing: CustSwitch(
                    value: SleepShake.enabled.isTrue,
                    onChanged: SleepShake.setEnabled,
                  ),
                ),
              ],
              const AutoSleepTimerTile(),
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
                          AutoSleepTimer.rememberMinutes(dur);
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
              // A length of your own, as in Pocket Casts and AntennaPod.
              RiffSheetTile(
                icon: Icons.more_time_rounded,
                title: 'customSleepTimer'.tr,
                onTap: () async {
                  final minutes = await showCustomSleepTimerDialog(context);
                  if (minutes == null || !context.mounted) return;
                  final ok = playerController.startSleepTimer(minutes);
                  AutoSleepTimer.rememberMinutes(minutes);
                  _done(context,
                      ok ? 'sleepTimeSetAlert'.tr : 'operationFailed'.tr);
                },
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
              const AutoSleepTimerTile(),
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

/// The automatic sleep timer (AntennaPod's): the switch, saying for how
/// long and between which hours, and while it's on, those hours to change.
class AutoSleepTimerTile extends StatelessWidget {
  const AutoSleepTimerTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Obx(() {
      final on = AutoSleepTimer.enabled.value;
      final from = AutoSleepTimer.from.value;
      final to = AutoSleepTimer.to.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffSheetTile(
            icon: Icons.schedule_rounded,
            title: 'autoSleepTimer'.tr,
            subtitle:
                (from == to ? 'autoSleepTimerAllDay' : 'autoSleepTimerDes')
                    .trParams({
              'time': formatSleepMinutes(AutoSleepTimer.minutes),
              'from': sleepHourLabel(context, from),
              'to': sleepHourLabel(context, to),
            }),
            onTap: () => AutoSleepTimer.setEnabled(!on),
            trailing: CustSwitch(
              value: on,
              onChanged: AutoSleepTimer.setEnabled,
            ),
          ),
          if (on)
            Padding(
              // Under the tile's text.
              padding: const EdgeInsets.only(
                  left: RiffSpacing.lg +
                      RiffComponentSizes.sheetIcon +
                      RiffSpacing.lg,
                  right: RiffSpacing.lg),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RiffSpacing.lg,
                children: [
                  _HourDropdown(
                    label: 'autoSleepTimerFrom'.tr,
                    labelStyle: labelStyle,
                    hour: from,
                    onChanged: (h) => AutoSleepTimer.setHours(fromHour: h),
                  ),
                  _HourDropdown(
                    label: 'autoSleepTimerTo'.tr,
                    labelStyle: labelStyle,
                    hour: to,
                    onChanged: (h) => AutoSleepTimer.setHours(toHour: h),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// [hour] o'clock as the phone tells the time ("22:00", "10:00 PM").
String sleepHourLabel(BuildContext context, int hour) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: hour, minute: 0),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));

/// One of the automatic sleep timer's hours ([label]: From, Until), to
/// pick from the 24; read out with its label.
class _HourDropdown extends StatelessWidget {
  const _HourDropdown(
      {required this.label,
      required this.labelStyle,
      required this.hour,
      required this.onChanged});

  final String label;
  final TextStyle? labelStyle;
  final int hour;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(width: RiffSpacing.sm),
          DropdownButton<int>(
            dropdownColor: Theme.of(context).colorScheme.surfaceContainerLow,
            underline: const SizedBox.shrink(),
            value: hour,
            items: [
              for (var h = 0; h < Duration.hoursPerDay; h++)
                DropdownMenuItem(
                    value: h, child: Text(sleepHourLabel(context, h))),
            ],
            onChanged: (h) {
              if (h != null) onChanged(h);
            },
          ),
        ],
      ),
    );
  }
}

/// "1 h 30 min".
String formatSleepMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m ${'minShort'.tr}';
  if (m == 0) return '$h ${'hourShort'.tr}';
  return '$h ${'hourShort'.tr} $m ${'minShort'.tr}';
}

/// AppPrefs key of the last custom sleep timer length, in minutes.
const customSleepMinutesKey = 'sleepTimerCustomMinutes';

/// Asks for a sleep timer length of your own: minutes, or null.
Future<int?> showCustomSleepTimerDialog(BuildContext context) =>
    showDialog<int>(
      context: context,
      builder: (_) => const CustomSleepTimerDialog(),
    );

/// A slider from 5 minutes to 4 hours in 5-minute steps, starting at the
/// length picked last time.
class CustomSleepTimerDialog extends StatefulWidget {
  const CustomSleepTimerDialog({super.key});

  static const int minMinutes = 5;
  static const int maxMinutes = 240;
  static const int step = 5;
  static const int fallback = 20;

  @override
  State<CustomSleepTimerDialog> createState() => _CustomSleepTimerDialogState();
}

class _CustomSleepTimerDialogState extends State<CustomSleepTimerDialog> {
  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  late int _minutes = () {
    final saved = _prefs?.get(customSleepMinutesKey);
    return saved is int
        ? saved.clamp(CustomSleepTimerDialog.minMinutes,
            CustomSleepTimerDialog.maxMinutes)
        : CustomSleepTimerDialog.fallback;
  }();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const min = CustomSleepTimerDialog.minMinutes;
    const max = CustomSleepTimerDialog.maxMinutes;
    return AlertDialog(
      title: Text('sleepTimer'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatSleepMinutes(_minutes),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: RiffSpacing.sm),
          Slider(
            value: _minutes.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ CustomSleepTimerDialog.step,
            label: formatSleepMinutes(_minutes),
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        FilledButton(
          onPressed: () {
            _prefs?.put(customSleepMinutesKey, _minutes);
            Navigator.of(context).pop(_minutes);
          },
          child: Text('startSleepTimer'.tr),
        ),
      ],
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
