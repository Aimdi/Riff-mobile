import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_playback_profile.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/theme_controller.dart';
import '../../widgets/cust_switch.dart';
import '../../widgets/riff_sheet.dart';
import '../Home/home_layout.dart';
import '../Settings/settings_screen_controller.dart';

/// "1×", "1.25×", "2.5×".
String podcastSpeedLabel(double speed) {
  var s = speed.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$s×';
}

/// Skip glyph for any length: Material's numbered icons where they exist
/// (5, 10, 30), otherwise the plain arrow with the number on it.
class SkipSecondsIcon extends StatelessWidget {
  const SkipSecondsIcon(
      {super.key,
      required this.seconds,
      required this.forward,
      this.color,
      this.size = 34});
  final int seconds;
  final bool forward;
  final Color? color;
  final double size;

  static IconData? _numbered(int seconds, bool forward) => switch (seconds) {
        5 => forward ? Icons.forward_5_rounded : Icons.replay_5_rounded,
        10 => forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
        30 => forward ? Icons.forward_30_rounded : Icons.replay_30_rounded,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final numbered = _numbered(seconds, forward);
    if (numbered != null) return Icon(numbered, color: color, size: size);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(
            flipX: forward,
            child: Icon(Icons.replay_rounded, color: color, size: size),
          ),
          Padding(
            padding: EdgeInsets.only(top: size * 0.12),
            child: Text(
              '$seconds',
              style: TextStyle(
                fontSize: size * 0.27,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skip back / forward in the long-form player. Podcast episodes use their
/// show's lengths; audiobooks keep −10 s / +30 s.
class LongFormSkipButton extends StatelessWidget {
  const LongFormSkipButton(
      {super.key, required this.forward, this.color, this.size = 38});
  final bool forward;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    return Obx(() {
      PodcastPlaybackPrefs.rev.value;
      pc.currentSong.value;
      final podcast = pc.isCurrentSongPodcast;
      final profile = podcast ? pc.currentPodcastProfile : null;
      final secs = forward
          ? (profile?.skipForwardSec ?? 30)
          : (profile?.skipBackSec ?? 10);
      return IconButton(
        tooltip: forward ? '+${secs}s' : '−${secs}s',
        iconSize: size,
        onPressed: () =>
            pc.seekBy(Duration(seconds: forward ? secs : -secs)),
        icon: SkipSecondsIcon(
            seconds: secs, forward: forward, color: color, size: size),
      );
    });
  }
}

/// Speed pill in the podcast player: shows the episode's speed, opens the
/// speed sheet.
class PodcastSpeedButton extends StatelessWidget {
  const PodcastSpeedButton({super.key, required this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    return Tooltip(
      message: 'speed'.tr,
      child: InkWell(
        onTap: () => showPodcastSpeedSheet(context),
        customBorder: const StadiumBorder(),
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                  color: (color ?? RiffSurfaces.textPrimary).withOpacity(0.35)),
            ),
          ),
          child: Obx(() {
            PodcastPlaybackPrefs.rev.value;
            pc.currentSong.value;
            return Text(
              podcastSpeedLabel(pc.currentPodcastProfile.speed),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color),
            );
          }),
        ),
      ),
    );
  }
}

Future<void> showPodcastSpeedSheet(BuildContext context) {
  final pc = Get.find<PlayerController>();
  return showModalBottomSheet<void>(
    context: pc.homeScaffoldkey.currentContext ?? context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 500),
    shape: riffSheetShape,
    builder: (sheet) => SafeArea(
      top: false,
      child: Obx(() {
        PodcastPlaybackPrefs.rev.value;
        final song = pc.currentSong.value;
        final key = song == null ? null : podcastShowKey(song);
        final custom = PodcastPlaybackPrefs.hasShowOverride(key);
        final profile = pc.currentPodcastProfile;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('speed'.tr,
                subtitle: custom
                    ? 'savedForThisShow'.tr
                    : 'savedForAllPodcasts'.tr),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: PodcastSpeedPicker(
                speed: profile.speed,
                onChanged: (v) => pc.updateCurrentPodcastProfile(
                    (p) => p.copyWith(speed: v)),
              ),
            ),
          ],
        );
      }),
    ),
  );
}

/// Big speed readout, a 0.5–3.0 slider in 0.1 steps and quick chips.
class PodcastSpeedPicker extends StatelessWidget {
  const PodcastSpeedPicker(
      {super.key, required this.speed, required this.onChanged});
  final double speed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color;
    final steps = ((PodcastPlaybackProfile.maxSpeed -
                PodcastPlaybackProfile.minSpeed) *
            10)
        .round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(podcastSpeedLabel(speed),
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, color: fg)),
            const Spacer(),
            IconButton(
              tooltip: 'slower'.tr,
              onPressed: speed <= PodcastPlaybackProfile.minSpeed
                  ? null
                  : () => onChanged(speed - 0.1),
              icon: const Icon(Icons.remove_rounded),
            ),
            IconButton(
              tooltip: 'faster'.tr,
              onPressed: speed >= PodcastPlaybackProfile.maxSpeed
                  ? null
                  : () => onChanged(speed + 0.1),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Slider(
          min: PodcastPlaybackProfile.minSpeed,
          max: PodcastPlaybackProfile.maxSpeed,
          divisions: steps,
          value: speed.clamp(
              PodcastPlaybackProfile.minSpeed, PodcastPlaybackProfile.maxSpeed),
          label: podcastSpeedLabel(speed),
          onChanged: onChanged,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in PodcastPlaybackProfile.speedChips)
              RiffChoiceChip(
                label: podcastSpeedLabel(s),
                selected: (s - speed).abs() < 0.001,
                onTap: () => onChanged(s),
              ),
          ],
        ),
      ],
    );
  }
}

/// Every playback setting of a [PodcastPlaybackProfile]: used for the
/// global defaults (Podcast settings) and a show's overrides.
class PodcastPlaybackEditor extends StatelessWidget {
  const PodcastPlaybackEditor(
      {super.key, required this.profile, required this.onChanged});
  final PodcastPlaybackProfile profile;
  final ValueChanged<PodcastPlaybackProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final android = GetPlatform.isAndroid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'speed'.tr),
        PodcastSpeedPicker(
          speed: profile.speed,
          onChanged: (v) => onChanged(profile.copyWith(speed: v)),
        ),
        _label(context, 'skipBack'.tr),
        _skipChips(profile.skipBackSec, false,
            (v) => onChanged(profile.copyWith(skipBackSec: v))),
        _label(context, 'skipForward'.tr),
        _skipChips(profile.skipForwardSec, true,
            (v) => onChanged(profile.copyWith(skipForwardSec: v))),
        if (android) ...[
          const SizedBox(height: 14),
          _switchRow(
            context,
            title: 'trimSilence'.tr,
            subtitle: 'trimSilenceDes'.tr,
            value: profile.trimSilence,
            onChanged: (v) => onChanged(profile.copyWith(trimSilence: v)),
          ),
          _label(context, 'voiceBoost'.tr),
          Text('voiceBoostDes'.tr, style: homeCardSubtitleStyle(context)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in PodcastVoiceBoost.values)
                RiffChoiceChip(
                  label: 'voiceBoost_${v.name}'.tr,
                  selected: profile.voiceBoost == v,
                  onTap: () => onChanged(profile.copyWith(voiceBoost: v)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _switchRow(
          context,
          title: 'segmentSkipping'.tr,
          subtitle: 'segmentSkippingDes'.tr,
          value: profile.segmentSkip,
          onChanged: (v) => onChanged(profile.copyWith(segmentSkip: v)),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text.toUpperCase(), style: homeSectionLabelStyle(context)),
      );

  Widget _skipChips(int value, bool forward, ValueChanged<int> onTap) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in PodcastPlaybackProfile.skipChoices)
            RiffChoiceChip(
              label: forward ? '+$s s' : '−$s s',
              selected: s == value,
              onTap: () => onTap(s),
            ),
        ],
      );

  Widget _switchRow(BuildContext context,
          {required String title,
          required String subtitle,
          required bool value,
          required ValueChanged<bool> onChanged}) =>
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: homeCardSubtitleStyle(context)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CustSwitch(value: value, onChanged: onChanged),
        ],
      );
}

/// Applies settings to what is playing when it belongs to podcasts.
void _refreshIfPodcastPlaying() {
  if (!Get.isRegistered<PlayerController>()) return;
  final pc = Get.find<PlayerController>();
  if (pc.isCurrentSongPodcast) pc.refreshPlaybackProfile();
}

/// A show's "Playback settings": edits create or update the show's own
/// settings; "Use global defaults" drops them again.
Future<void> showPodcastShowPlaybackSheet(BuildContext context,
    {required String showKey, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: riffSheetShape,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => Obx(() {
        PodcastPlaybackPrefs.rev.value;
        final custom = PodcastPlaybackPrefs.hasShowOverride(showKey);
        final profile = PodcastPlaybackPrefs.forShow(showKey);
        return ListView(
          controller: scroll,
          padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 20),
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('playbackSettings'.tr, subtitle: title),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Icon(
                      custom
                          ? Icons.tune_rounded
                          : Icons.public_rounded,
                      size: 18,
                      color: homeMutedColor(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      custom
                          ? 'showUsesOwnSettings'.tr
                          : 'showUsesDefaults'.tr,
                      style: homeCardSubtitleStyle(context)
                          .copyWith(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: custom
                        ? () async {
                            await PodcastPlaybackPrefs.clearShowOverride(
                                showKey);
                            _refreshIfPodcastPlaying();
                          }
                        : null,
                    style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.secondary),
                    child: Text('useGlobalDefaults'.tr),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PodcastPlaybackEditor(
                profile: profile,
                onChanged: (p) async {
                  await PodcastPlaybackPrefs.setShowOverride(showKey, p);
                  _refreshIfPodcastPlaying();
                },
              ),
            ),
          ],
        );
      }),
    ),
  );
}

/// Saves the global podcast defaults (Podcast settings).
Future<void> savePodcastDefaults(PodcastPlaybackProfile p) async {
  await PodcastPlaybackPrefs.setGlobalDefaults(p);
  // The ad-skip toggle is shared: keep its on-screen mirror in step.
  if (Get.isRegistered<SettingsScreenController>()) {
    Get.find<SettingsScreenController>().podcastAutoSkipAdsEnabled.value =
        p.segmentSkip;
  }
  _refreshIfPodcastPlaying();
}
