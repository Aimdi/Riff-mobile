import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
                padding: const EdgeInsets.fromLTRB(
                    HomeLayout.gutter + 4, 0, HomeLayout.gutter + 4, 200),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('podcastPlaybackDefaults'.tr,
                        style: homeSectionTitleStyle(context)),
                  ),
                  const SizedBox(height: 4),
                  Text('podcastPlaybackDefaultsDes'.tr,
                      style: homeCardSubtitleStyle(context)
                          .copyWith(fontSize: 13)),
                  PodcastPlaybackEditor(
                    profile: defaults,
                    onChanged: savePodcastDefaults,
                  ),
                  const SizedBox(height: 28),
                  const PodcastSegmentSettings(),
                  const SizedBox(height: 28),
                  const PodcastLibrarySettings(),
                  const SizedBox(height: 28),
                  Text('podcastPlayerLook'.tr,
                      style: homeSectionTitleStyle(context)),
                  const SizedBox(height: 10),
                  Obx(() {
                    PodcastPlayerTint.enabledRx.value;
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('podcastTintPlayer'.tr,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('podcastTintPlayerDes'.tr,
                                  style: homeCardSubtitleStyle(context)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        CustSwitch(
                          value: PodcastPlayerTint.enabled,
                          onChanged: PodcastPlayerTint.setEnabled,
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 28),
                  Text('podcastResume'.tr,
                      style: homeSectionTitleStyle(context)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('smartResume'.tr,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('smartResumeDes'.tr,
                                style: homeCardSubtitleStyle(context)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
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
