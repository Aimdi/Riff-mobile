import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/quick_picks.dart';
import '../player/player_controller.dart';
import '../utils/riff_tokens.dart';
import 'image_widget.dart';
import 'songinfo_bottom_sheet.dart';

class QuickPicksWidget extends StatelessWidget {
  const QuickPicksWidget(
      {super.key, required this.content, this.scrollController});
  final QuickPicks content;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    // 2 rows (~230) on phone; keep a bit taller on desktop for touch targets.
    final height = GetPlatform.isDesktop ? 248.0 : 232.0;
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
                    return Listener(
                      onPointerDown: (PointerDownEvent event) {
                        if (event.buttons == kSecondaryMouseButton) {
                          //show songinfobotomsheet
                          showModalBottomSheet(
                            useRootNavigator: true,
                            constraints: const BoxConstraints(maxWidth: 500),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(10.0)),
                            ),
                            isScrollControlled: true,
                            context: playerController
                                .homeScaffoldkey.currentState!.context,
                            barrierColor: Colors.transparent.withAlpha(100),
                            builder: (context) => SongInfoBottomSheet(
                              content.songList[item],
                            ),
                          ).whenComplete(
                              () => Get.delete<SongInfoController>());
                        }
                      },
                      child: ListTile(
                          contentPadding:
                              const EdgeInsets.only(left: 0, right: 8),
                          leading: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(RiffTokens.radiusSm),
                            child: ImageWidget(
                              song: content.songList[item],
                              size: 52,
                            ),
                          ),
                          title: Text(
                            content.songList[item].title,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            "${content.songList[item].artist}",
                            maxLines: 1,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          onTap: () {
                            playerController
                                .pushSongToQueue(content.songList[item]);
                          },
                          onLongPress: () {
                            showModalBottomSheet(
                              useRootNavigator: true,
                              constraints: const BoxConstraints(maxWidth: 500),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(10.0)),
                              ),
                              isScrollControlled: true,
                              context: playerController
                                  .homeScaffoldkey.currentState!.context,
                              //constraints: BoxConstraints(maxHeight:Get.height),
                              barrierColor: Colors.transparent.withAlpha(100),
                              builder: (context) =>
                                  SongInfoBottomSheet(content.songList[item]),
                            ).whenComplete(
                                () => Get.delete<SongInfoController>());
                          },
                          trailing: (GetPlatform.isDesktop)
                              ? IconButton(
                                  splashRadius: 20,
                                  onPressed: () {
                                    showModalBottomSheet(
                                      useRootNavigator: true,
                                      constraints:
                                          const BoxConstraints(maxWidth: 500),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(10.0)),
                                      ),
                                      isScrollControlled: true,
                                      context: playerController.homeScaffoldkey
                                          .currentState!.context,
                                      //constraints: BoxConstraints(maxHeight:Get.height),
                                      barrierColor:
                                          Colors.transparent.withAlpha(100),
                                      builder: (context) => SongInfoBottomSheet(
                                          content.songList[item]),
                                    ).whenComplete(
                                        () => Get.delete<SongInfoController>());
                                  },
                                  icon: const Icon(Icons.more_vert))
                              : null),
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
