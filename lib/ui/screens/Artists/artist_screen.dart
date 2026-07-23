import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '/models/playlist.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Artists/artist_screen_v2.dart';
import '/ui/screens/Podcasts/podcasts_library_controller.dart';
import '/ui/widgets/image_widget.dart';
import '../../widgets/loader.dart';
import '../../widgets/separate_tab_item_widget.dart';
import '../../widgets/snackbar.dart';
import 'artist_screen_controller.dart';
import 'spotify_artist_view.dart';

class ArtistScreen extends StatelessWidget {
  const ArtistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final tag = key.hashCode.toString();
    final ArtistScreenController artistScreenController =
        Get.isRegistered<ArtistScreenController>(tag: tag)
            ? Get.find<ArtistScreenController>(tag: tag)
            : Get.put(ArtistScreenController(), tag: tag);
    return Scaffold(
      floatingActionButton: Obx(
        () => Padding(
          padding: EdgeInsets.only(
              bottom: playerController.playerPanelMinHeight.value),
          child: SizedBox(
            height: 60,
            width: 60,
            child: FittedBox(
              child: FloatingActionButton(
                  focusElevation: 0,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14))),
                  elevation: 0,
                  onPressed: () async {
                    final radioId = artistScreenController.artist_.radioId;
                    if (radioId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                          context, "radioNotAvailable".tr,
                          size: SanckBarSize.BIG));
                      return;
                    }
                    playerController.startRadio(null,
                        playlistid: artistScreenController.artist_.radioId);
                  },
                  child: const Icon(Icons.sensors)),
            ),
          ),
        ),
      ),
      body: GetPlatform.isDesktop
          ? ArtistScreenBN(
              artistScreenController: artistScreenController, tag: tag)
          : SpotifyArtistView(controller: artistScreenController),
    );
  }

  NavigationRailDestination railDestination(String label) {
    return NavigationRailDestination(
      icon: const SizedBox.shrink(),
      label: RotatedBox(quarterTurns: -1, child: Text(label)),
    );
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
    required this.tag,
  });

  final String tag;

  @override
  Widget build(BuildContext context) {
    final ArtistScreenController artistScreenController =
        Get.find<ArtistScreenController>(tag: tag);

    final tabIndex = artistScreenController.navigationRailCurrentIndex.value;

    if (tabIndex == 0) {
      return Obx(() => artistScreenController.isArtistContentFetced.isTrue
          ? AboutArtist(
              artistScreenController: artistScreenController,
            )
          : const Center(
              child: LoadingIndicator(),
            ));
    } else {
      final separatedContent = artistScreenController.sepataredContent;
      final currentTabName =
          ["About", "Songs", "Videos", "Albums", "Singles"][tabIndex];
      return Obx(() {
        if (artistScreenController.isSeparatedArtistContentFetced.isFalse &&
            artistScreenController.navigationRailCurrentIndex.value != 0) {
          return const Center(child: LoadingIndicator());
        }
        return SeparateTabItemWidget(
          artistControllerTag: tag,
          isResultWidget: false,
          items: separatedContent.containsKey(currentTabName)
              ? separatedContent[currentTabName]['results']
              : [],
          title: currentTabName,
          topPadding: context.isLandscape ? 50.0 : 80.0,
          scrollController: currentTabName == "Songs"
              ? artistScreenController.songScrollController
              : currentTabName == "Videos"
                  ? artistScreenController.videoScrollController
                  : currentTabName == "Albums"
                      ? artistScreenController.albumScrollController
                      : currentTabName == "Singles"
                          ? artistScreenController.singlesScrollController
                          : null,
        );
      });
    }
  }
}

class AboutArtist extends StatelessWidget {
  const AboutArtist(
      {super.key,
      required this.artistScreenController,
      this.padding = const EdgeInsets.only(bottom: 90, top: 70)});
  final EdgeInsetsGeometry padding;
  final ArtistScreenController artistScreenController;

  @override
  Widget build(BuildContext context) {
    final artistData = artistScreenController.artistData;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          padding: padding,
          child: artistScreenController.isArtistContentFetced.value
              ? Column(
                  children: [
                    SizedBox(
                      height: 200,
                      width: 260,
                      child: Stack(
                        children: [
                          Center(
                            child: ImageWidget(
                              size: 200,
                              artist: artistScreenController.artist_,
                            ),
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: Column(
                              children: [
                                InkWell(
                                    onTap: () {
                                      final bool add = artistScreenController
                                          .isAddedToLibrary.isFalse;
                                      artistScreenController
                                          .addNremoveFromLibrary(add: add)
                                          .then((value) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(snackbar(
                                                  context,
                                                  value
                                                      ? add
                                                          ? "artistBookmarkAddAlert"
                                                              .tr
                                                          : "artistBookmarkRemoveAlert"
                                                              .tr
                                                      : "operationFailed".tr,
                                                  size: SanckBarSize.MEDIUM));
                                        }
                                      });
                                    },
                                    child: Obx(
                                      () => artistScreenController
                                              .isArtistContentFetced.isFalse
                                          ? const SizedBox.shrink()
                                          : Icon(artistScreenController
                                                  .isAddedToLibrary.isFalse
                                              ? Icons.bookmark_add
                                              : Icons.bookmark_added),
                                    )),
                                Obx(() {
                                  if (artistScreenController
                                      .isArtistContentFetced.isFalse) {
                                    return const SizedBox.shrink();
                                  }
                                  final id = artistScreenController
                                      .artist_.browseId;
                                  if (!Get.isRegistered<
                                      LibraryPodcastsController>()) {
                                    return const SizedBox.shrink();
                                  }
                                  final lib =
                                      Get.find<LibraryPodcastsController>();
                                  // Touch the list so Obx rebuilds on subscribe.
                                  final subscribed = lib.libraryPodcasts
                                      .any((p) => p.playlistId == id);
                                  return IconButton(
                                    tooltip: subscribed
                                        ? 'alreadySubscribedPodcast'.tr
                                        : 'subscribeYoutubeChannel'.tr,
                                    icon: Icon(
                                      subscribed
                                          ? Icons.podcasts
                                          : Icons.podcasts_outlined,
                                      size: 20,
                                    ),
                                    splashRadius: 18,
                                    onPressed: () async {
                                      if (subscribed) {
                                        await lib.removeFromLibrary(id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(snackbar(
                                            context,
                                            'removeFromLib'.tr,
                                            size: SanckBarSize.MEDIUM,
                                          ));
                                        }
                                        return;
                                      }
                                      final pl = Playlist(
                                        title: artistScreenController
                                            .artist_.name,
                                        playlistId: id,
                                        thumbnailUrl: artistScreenController
                                            .artist_.thumbnailUrl,
                                        description: artistScreenController
                                                .artist_.subscribers ??
                                            'YouTube channel',
                                        kind: 'yt_channel',
                                      );
                                      await lib.addToLibrary(pl);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(snackbar(
                                          context,
                                          'subscribedAsPodcast'.tr,
                                          size: SanckBarSize.MEDIUM,
                                        ));
                                      }
                                    },
                                  );
                                }),
                                IconButton(
                                    icon: const Icon(
                                      Icons.share,
                                      size: 20,
                                    ),
                                    splashRadius: 18,
                                    onPressed: () => Share.share(
                                        "https://music.youtube.com/channel/${artistScreenController.artist_.browseId}")),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 10),
                      child: Text(
                        artistScreenController.artist_.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    (artistData.containsKey("description") &&
                            artistData["description"] != null)
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "\"${artistData["description"]}\"",
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          )
                        : SizedBox(
                            height: 300,
                            child: Center(
                              child: Text(
                                "artistDesNotAvailable".tr,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
