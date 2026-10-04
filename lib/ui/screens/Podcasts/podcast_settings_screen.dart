import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/services/podcast_playback_profile.dart';
import '../../widgets/cust_switch.dart';
import '../Home/home_layout.dart';
import '/ui/player/components/podcast_player_tint.dart';
import 'podcast_library_ui.dart';
import 'podcast_playback_controls.dart';
import 'podcast_segment_ui.dart';

/// "Podcast settings", opened from the gear in the Podcasts tab header.
/// Everything here applies to podcast episodes only; music keeps its own
/// settings.
class PodcastSettingsScreen extends StatelessWidget {
  const PodcastSettingsScreen({super.key});

  /// Space between setting groups; a hairline runs through its middle.
  static const double _groupGap = RiffSpacing.xxl + RiffSpacing.xs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader('podcastSettings'.tr,
              subtitle: 'podcastSettingsDes'.tr),
          Expanded(
            child: Obx(() {
              PodcastPlaybackPrefs.rev.value;
              final defaults = PodcastPlaybackPrefs.globalDefaults;
              final smartResume = PodcastPlaybackPrefs.smartResume;
              return ListView(
                padding: const EdgeInsets.only(
                    left: HomeLayout.gutter + RiffSpacing.xs,
                    right: HomeLayout.gutter + RiffSpacing.xs,
                    bottom: RiffSpacing.listEnd),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: RiffSpacing.md),
                    child: Text('podcastPlaybackDefaults'.tr,
                        style: homeSectionTitleStyle(context)),
                  ),
                  const SizedBox(height: RiffSpacing.xs),
                  Text('podcastPlaybackDefaultsDes'.tr,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: homeMutedColor(context))),
                  PodcastPlaybackEditor(
                    profile: defaults,
                    onChanged: savePodcastDefaults,
                  ),
                  const Divider(height: _groupGap),
                  const PodcastSegmentSettings(),
                  const Divider(height: _groupGap),
                  const PodcastLibrarySettings(),
                  const Divider(height: _groupGap),
                  Text('podcastPlayerLook'.tr,
                      style: homeSectionTitleStyle(context)),
                  const SizedBox(height: RiffSpacing.sm),
                  Obx(() {
                    PodcastPlayerTint.enabledRx.value;
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('podcastTintPlayer'.tr,
                                  style: Theme.of(context).textTheme.bodyLarge),
                              const SizedBox(height: RiffSpacing.xxs),
                              Text('podcastTintPlayerDes'.tr,
                                  style: homeCardSubtitleStyle(context)),
                            ],
                          ),
                        ),
                        const SizedBox(width: RiffSpacing.md),
                        CustSwitch(
                          value: PodcastPlayerTint.enabled,
                          onChanged: PodcastPlayerTint.setEnabled,
                        ),
                      ],
                    );
                  }),
                  const Divider(height: _groupGap),
                  Text('podcastResume'.tr,
                      style: homeSectionTitleStyle(context)),
                  const SizedBox(height: RiffSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('smartResume'.tr,
                                style: Theme.of(context).textTheme.bodyLarge),
                            const SizedBox(height: RiffSpacing.xxs),
                            Text('smartResumeDes'.tr,
                                style: homeCardSubtitleStyle(context)),
                          ],
                        ),
                      ),
                      const SizedBox(width: RiffSpacing.md),
                      CustSwitch(
                        value: smartResume,
                        onChanged: PodcastPlaybackPrefs.setSmartResume,
                      ),
                    ],
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
