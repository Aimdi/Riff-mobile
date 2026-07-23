import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:get/get.dart';

import '../../widgets/loader.dart';
import '../player_controller.dart';
import 'word_synced_lyrics.dart';

class LyricsWidget extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const LyricsWidget({super.key, required this.padding});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(
      () => playerController.isLyricsLoading.isTrue
          ? const Center(
              child: LoadingIndicator(),
            )
          : playerController.lyricsMode.toInt() == 1
              ? Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: padding,
                    child: Obx(
                      () => TextSelectionTheme(
                        data: Theme.of(context).textSelectionTheme,
                        child: SelectableText(
                          playerController.lyrics["plainLyrics"] == "NA"
                              ? "lyricsNotAvailable".tr
                              : playerController.lyrics["plainLyrics"] ?? "",
                          textAlign: TextAlign.center,
                          style: playerController.isDesktopLyricsDialogOpen
                              ? Theme.of(context).textTheme.titleMedium!
                              : Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                )
              : _syncedBody(context, playerController),
    );
  }

  Widget _syncedBody(BuildContext context, PlayerController playerController) {
    final ttml = (playerController.lyrics['ttml'] ?? '').toString();
    if (ttml.isNotEmpty) {
      return WordSyncedLyricsWidget(ttml: ttml, padding: padding);
    }
    return IgnorePointer(
      child: LyricsReader(
        padding: const EdgeInsets.only(left: 5, right: 5),
        lyricUi: playerController.lyricUi,
        position:
            playerController.progressBarStatus.value.current.inMilliseconds,
        model: LyricsModelBuilder.create()
            .bindLyricToMain(playerController.lyrics['synced'].toString())
            .getModel(),
        emptyBuilder: () => Center(
          child: Text(
            "syncedLyricsNotAvailable".tr,
            style: playerController.isDesktopLyricsDialogOpen
                ? Theme.of(context).textTheme.titleMedium!
                : Theme.of(context)
                    .textTheme
                    .titleMedium!
                    .copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
