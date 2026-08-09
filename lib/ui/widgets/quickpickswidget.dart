import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/quick_picks.dart';
import '../player/player_controller.dart';
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';
import 'image_widget.dart';
import 'songinfo_bottom_sheet.dart';

class QuickPicksWidget extends StatelessWidget {
  const QuickPicksWidget(
      {super.key, required this.content, this.scrollController});
  final QuickPicks content;
  final ScrollController? scrollController;

  void _openSongSheet(BuildContext context, PlayerController playerController,
      int item) {
    final sheetContext =
        playerController.homeScaffoldkey.currentContext ?? Get.context;
    if (sheetContext == null) return;
    showModalBottomSheet(
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(RiffTokens.radiusSm)),
      ),
      isScrollControlled: true,
      context: sheetContext,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (context) => SongInfoBottomSheet(
        content.songList[item],
      ),
    ).whenComplete(() => Get.delete<SongInfoController>());
  }

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    // 2 rows (~230) on phone; keep a bit taller on desktop for touch targets.
    final height = GetPlatform.isDesktop ? 248.0 : 232.0;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.65);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 12, top: 24, bottom: 10, right: 12),
                child: Text(
                  content.title == 'Quick picks' ||
                          content.title.toLowerCase().removeAllWhitespace ==
                              'quickpicks'
                      ? 'Quick picks'
                      : content.title.toLowerCase().removeAllWhitespace.tr,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        letterSpacing: -0.35,
                      ),
                ),
              )),
          Expanded(
            child: Scrollbar(
              thickness: GetPlatform.isDesktop ? null : 0,
              controller: scrollController,
              child: GridView.builder(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: content.songList.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: .34 / 1,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, item) {
                    final song = content.songList[item];
                    return Listener(
                      onPointerDown: (PointerDownEvent event) {
                        if (event.buttons == kSecondaryMouseButton) {
                          _openSongSheet(context, playerController, item);
                        }
                      },
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(RiffTokens.radiusSm),
                          onTap: () {
                            playerController.pushSongToQueue(song);
                          },
                          onLongPress: () {
                            _openSongSheet(context, playerController, item);
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      RiffTokens.radiusSm),
                                  child: ImageWidget(
                                    song: song,
                                    size: 52,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.15,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${song.artist}",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: muted,
                                              fontWeight: FontWeight.w400,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (GetPlatform.isDesktop)
                                  IconButton(
                                    splashRadius: 20,
                                    onPressed: () {
                                      _openSongSheet(
                                          context, playerController, item);
                                    },
                                    icon: const Icon(Icons.more_vert),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
            ),
          ),
          const SizedBox(height: 8)
        ],
      ),
    );
  }
}
