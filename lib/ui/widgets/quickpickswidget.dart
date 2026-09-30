import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/quick_picks.dart';
import '/services/discovery/discovery_types.dart';
import '../player/player_controller.dart';
import '../utils/riff_tokens.dart';
import '../screens/Home/home_layout.dart';
import 'image_widget.dart';
import 'snackbar.dart';
import 'songinfo_bottom_sheet.dart';

class QuickPicksWidget extends StatelessWidget {
  const QuickPicksWidget(
      {super.key, required this.content, this.scrollController});
  final QuickPicks content;
  final ScrollController? scrollController;

  void _openSongSheet(
      BuildContext context, PlayerController playerController, int item) {
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
    final title = content.title == 'Quick picks' ||
            content.title.toLowerCase().removeAllWhitespace == 'quickpicks'
        ? 'Quick picks'
        : content.title.toLowerCase().removeAllWhitespace.tr;
    const rowHeight = 60.0;
    const rowGap = 4.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title),
        SizedBox(
          height: rowHeight * 2 + rowGap,
          child: LayoutBuilder(builder: (context, constraints) {
            // Leave a peek of the next column so the grid reads as scrollable.
            final rowWidth = (constraints.maxWidth - HomeLayout.gutter - 40)
                .clamp(220.0, 340.0);
            return Scrollbar(
              thickness: GetPlatform.isDesktop ? null : 0,
              controller: scrollController,
              child: GridView.builder(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
                  itemCount: content.songList.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: rowWidth,
                    crossAxisSpacing: rowGap,
                    mainAxisSpacing: HomeLayout.cardGap,
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
                          onTap: () async {
                            final ok = await playerController.playPlayListSong(
                                content.songList, item,
                                source: DiscoverySource.home);
                            if (!ok) snackOperationFailed();
                          },
                          onLongPress: () {
                            _openSongSheet(context, playerController, item);
                          },
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(RiffTokens.radiusSm),
                                child: ImageWidget(
                                  song: song,
                                  size: 52,
                                  borderRadius: 0,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: homeCardTitleStyle(context)
                                          .copyWith(fontSize: 14.5),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      song.artist ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: homeCardSubtitleStyle(context)
                                          .copyWith(fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 22,
                                color: homeMutedColor(context),
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
                    );
                  }),
            );
          }),
        ),
      ],
    );
  }
}
