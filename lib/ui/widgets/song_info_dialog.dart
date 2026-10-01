import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

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
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: RiffDialogTitle("songInfo".tr,
                  icon: Icons.info_outline_rounded),
            ),
            Expanded(
                child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
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
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Theme.of(context).colorScheme.secondary)),
          const SizedBox(height: 2),
          TextSelectionTheme(
            data: Theme.of(context).textSelectionTheme,
            child: SelectableText(
              value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.titleMedium?.color),
            ),
          )
        ],
      ),
    );
  }
}
