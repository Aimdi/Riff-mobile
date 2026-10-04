import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/common_dialog_widget.dart';

class SongInfoDialog extends StatelessWidget {
  final MediaItem song;
  const SongInfoDialog({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    Map<dynamic, dynamic> streamInfo = _getStreamInfo(song.id);
    return CommonDialog(
      child: SizedBox(
        height: Get.mediaQuery.size.height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.xl,
                  top: RiffSpacing.xxl,
                  right: RiffSpacing.xl,
                  bottom: RiffSpacing.md),
              child: RiffDialogTitle("songInfo".tr,
                  icon: Icons.info_outline_rounded),
            ),
            Expanded(
                child: ListView(
              padding: const EdgeInsets.symmetric(vertical: RiffSpacing.xs),
              children: [
                InfoItem(title: "id".tr, value: song.id),
                InfoItem(title: "title".tr, value: song.title),
                InfoItem(title: "album".tr, value: song.album ?? "NA"),
                InfoItem(title: "artists".tr, value: song.artist ?? "NA"),
                InfoItem(
                    title: "duration".tr,
                    value:
                        "${streamInfo["approxDurationMs"] ?? song.duration?.inMilliseconds ?? "NA"} ms"),
                InfoItem(
                    title: "audioCodec".tr,
                    value: streamInfo["audioCodec"] ?? "NA"),
                InfoItem(
                    title: "bitrate".tr,
                    value: "${streamInfo["bitrate"] ?? "NA"}"),
                InfoItem(
                    title: "loudnessDb".tr,
                    value: "${streamInfo["loudnessDb"] ?? "NA"}"),
              ],
            )),
            Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.xl,
                  top: RiffSpacing.sm,
                  right: RiffSpacing.xl,
                  bottom: RiffSpacing.lg),
              child: RiffDialogButton("close".tr,
                  onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }

  Map<dynamic, dynamic> _getStreamInfo(String id) {
    Map<dynamic, dynamic> tempstreamInfo;
    final nullVal = {
      "audioCodec": null,
      "bitrate": null,
      "loudnessDb": null,
      "approxDurationMs": null
    };
    if (Hive.box("SongDownloads").containsKey(id)) {
      final song = Hive.box("SongDownloads").get(id);

      tempstreamInfo =
          song["streamInfo"] == null ? nullVal : song["streamInfo"][1];
    } else {
      final dbStreamData = Hive.box("SongsUrlCache").get(id);
      tempstreamInfo = dbStreamData != null &&
              dbStreamData.runtimeType.toString().contains("Map")
          ? dbStreamData[Hive.box('AppPrefs').get('streamingQuality') == 0
              ? 'lowQualityAudio'
              : "highQualityAudio"]
          : nullVal;
    }
    return tempstreamInfo;
  }
}

class InfoItem extends StatelessWidget {
  final String title;
  final String value;
  const InfoItem({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Dialog text stays in the primary colour on surface1 (§5.11); the
    // label is the small caps caption, the value the row title.
    final fg = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RiffSpacing.xl, vertical: RiffSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(color: fg)),
          const SizedBox(height: RiffSpacing.xxs),
          TextSelectionTheme(
            data: theme.textSelectionTheme,
            child: SelectableText(
              value,
              style: theme.textTheme.titleMedium?.copyWith(color: fg),
            ),
          )
        ],
      ),
    );
  }
}
