import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/device_music.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';

import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';
import 'loader.dart';
import 'snackbar.dart';

class SongDownloadButton extends StatelessWidget {
  const SongDownloadButton(
      {super.key,
      this.calledFromPlayer = false,
      this.song_,
      this.isDownloadingDoneCallback});
  final bool calledFromPlayer;
  final MediaItem? song_;
  final void Function(bool)? isDownloadingDoneCallback;

  @override
  Widget build(BuildContext context) {
    final downloader = Get.find<Downloader>();
    final playerController = Get.find<PlayerController>();
    return Obx(() {
      final song =
          calledFromPlayer ? playerController.currentSong.value : song_;
      if (song == null && calledFromPlayer) return const SizedBox.shrink();
      final isDownloadingDone = (downloader.songQueue.contains(song) &&
          downloader.currentSong == song &&
          downloader.songDownloadingProgress.value == 100);
      if (isDownloadingDoneCallback != null) {
        isDownloadingDoneCallback!(isDownloadingDone);
      }

      // A music file on the phone (On this phone) is there already.
      final done = isDownloadingDone ||
          Hive.box("SongDownloads").containsKey(song!.id) ||
          DeviceMusic.isDeviceSong(song);
      final Widget state = done
          ? Icon(
              Icons.download_done,
              key: const ValueKey('done'),
              color: Theme.of(context).textTheme.titleMedium!.color,
              semanticLabel: 'downloaded'.tr,
            )
          : downloader.songQueue.contains(song) &&
                  downloader.isJobRunning.isTrue &&
                  downloader.currentSong == song
              ? Obx(
                  key: const ValueKey('progress'),
                  () => Semantics(
                        label: 'downloadingProgress'.trParams({
                          'percent':
                              '${downloader.songDownloadingProgress.value}'
                        }),
                        excludeSemantics: true,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                "${downloader.songDownloadingProgress.value}%",
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall!
                                    .copyWith(
                                        color: Theme.of(context)
                                            .textTheme
                                            .titleMedium!
                                            .color),
                              ),
                            ),
                            LoadingIndicator(
                              dimension: 30,
                              strokeWidth: 4,
                              value:
                                  (downloader.songDownloadingProgress.value) /
                                      100,
                            )
                          ],
                        ),
                      ))
              : downloader.songQueue.contains(song)
                  ? const LoadingIndicator(key: ValueKey('waiting'))
                  // While it fades out under the spinner, a second tap
                  // doesn't queue the song again.
                  : Obx(
                      key: const ValueKey('download'),
                      () => IgnorePointer(
                        ignoring: downloader.songQueue.contains(song),
                        child: IconButton(
                          tooltip: 'download'.tr,
                          icon: Icon(
                            Icons.download,
                            color:
                                Theme.of(context).textTheme.titleMedium!.color,
                          ),
                          onPressed: () {
                            (Hive.openBox("SongsCache").then((box) {
                              if (box.containsKey(song.id)) {
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                    snackbar(
                                        context, "songAlreadyOfflineAlert".tr,
                                        size: SanckBarSize.BIG));
                              } else {
                                HapticFeedback.lightImpact();
                                downloader.download(song);
                              }
                            }));
                          },
                        ),
                      ),
                    );

      // The states crossfade while the button eases between their sizes;
      // the tick pops in as the download finishes. Keyed by the song, so
      // the player's next song doesn't animate.
      return AnimatedSize(
        key: ValueKey(song?.id),
        duration: RiffDurations.select,
        curve: RiffDurations.selectCurve,
        child: RiffSwitcher(pop: done, child: state),
      );
    });
  }
}
