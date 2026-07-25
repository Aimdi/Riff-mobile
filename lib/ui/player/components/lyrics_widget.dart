import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:flutter_lyric/lyrics_reader_model.dart';
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
    return _SyncedLyricsReader(
      lyricsText: playerController.lyrics['synced'].toString(),
      emptyStyle: playerController.isDesktopLyricsDialogOpen
          ? Theme.of(context).textTheme.titleMedium!
          : Theme.of(context)
              .textTheme
              .titleMedium!
              .copyWith(color: Colors.white),
    );
  }
}

/// LRC reader that parses/lays out the lyric model ONCE per lyrics string.
/// Rebuilding the model on every position tick (the old inline approach)
/// re-measured every line and restarted the scroll animation ~5-60x/sec —
/// the lyrics looked laggy and never settled on the active line.
class _SyncedLyricsReader extends StatefulWidget {
  const _SyncedLyricsReader(
      {required this.lyricsText, required this.emptyStyle});
  final String lyricsText;
  final TextStyle emptyStyle;

  @override
  State<_SyncedLyricsReader> createState() => _SyncedLyricsReaderState();
}

class _SyncedLyricsReaderState extends State<_SyncedLyricsReader> {
  LyricsReaderModel? _model;
  String _builtFor = '';

  void _ensureModel() {
    if (_model != null && _builtFor == widget.lyricsText) return;
    _builtFor = widget.lyricsText;
    _model = LyricsModelBuilder.create()
        .bindLyricToMain(widget.lyricsText)
        .getModel();
  }

  @override
  Widget build(BuildContext context) {
    _ensureModel();
    final playerController = Get.find<PlayerController>();
    return IgnorePointer(
      child: Obx(
        () => LyricsReader(
          padding: const EdgeInsets.only(left: 5, right: 5),
          lyricUi: playerController.lyricUi,
          // Un-throttled lyrics clock — keeps highlighting on the beat
          // while the progress bar stays on its ~10 Hz fan-out.
          position: playerController.lyricsPositionMs.value,
          model: _model,
          emptyBuilder: () => Center(
            child: Text(
              "syncedLyricsNotAvailable".tr,
              style: widget.emptyStyle,
            ),
          ),
        ),
      ),
    );
  }
}
