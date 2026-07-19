import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:harmonymusic/utils/lang_mapping.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/common_dialog_widget.dart';
import '../../widgets/cust_switch.dart';
import '../../widgets/export_file_dialog.dart';
import '../../widgets/backup_dialog.dart';
import '../../widgets/restore_dialog.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '/ui/widgets/link_piped.dart';
import '/services/ban_service.dart';
import '/services/discovery/discovery_service.dart';
import '/services/listenbrainz_service.dart';
import '/services/music_service.dart';
import '/services/yt_auth_service.dart';
import 'yt_login_screen.dart';
import '../Home/home_screen_controller.dart';
import '../../navigator.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'components/custom_expansion_tile.dart';
import 'settings_screen_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    final isDesktop = GetPlatform.isDesktop;
    return Padding(
      padding: isBottomNavActive
          ? EdgeInsets.only(left: 20, top: topPadding, right: 15)
          : EdgeInsets.only(top: topPadding, left: 5, right: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "settings".tr,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
              child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 200, top: 20),
            children: [
              Obx(
                () => settingsController.isNewVersionAvailable.value
                    ? Padding(
                        padding: const EdgeInsets.only(
                            top: 8.0, right: 10, bottom: 8.0),
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            onTap: () {
                              launchUrl(
                                Uri.parse(
                                  'https://github.com/Aimdi/Riff-mobile/releases/latest',
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            tileColor: Theme.of(context).colorScheme.secondary,
                            contentPadding:
                                const EdgeInsets.only(left: 8, right: 10),
                            leading:
                                const CircleAvatar(child: Icon(Icons.download)),
                            title: Text("newVersionAvailable".tr),
                            visualDensity: const VisualDensity(horizontal: -2),
                            subtitle: Text(
                              "goToDownloadPage".tr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium!
                                  .copyWith(
                                      color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              CustomExpansionTile(
                title: "personalisation".tr,
                icon: Icons.palette,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("themeMode".tr),
                    subtitle: Obx(
                      () => Text(
                          settingsController.themeModetype.value ==
                                  ThemeType.dynamic
                              ? "dynamic".tr
                              : settingsController.themeModetype.value ==
                                      ThemeType.system
                                  ? "systemDefault".tr
                                  : settingsController.themeModetype.value ==
                                          ThemeType.dark
                                      ? "dark".tr
                                      : "light".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    onTap: () => showDialog(
                      context: context,
                      builder: (context) => const ThemeSelectorDialog(),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("language".tr),
                    subtitle: Text("languageDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => DropdownButton(
                        menuMaxHeight: Get.height - 250,
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox.shrink(),
                        style: Theme.of(context).textTheme.titleSmall,
                        value: settingsController.currentAppLanguageCode.value,
                        items: langMap.entries
                            .map((lang) => DropdownMenuItem(
                                  value: lang.key,
                                  child: Text(lang.value),
                                ))
                            .whereType<DropdownMenuItem<String>>()
                            .toList(),
                        selectedItemBuilder: (context) =>
                            langMap.entries.map<Widget>((item) {
                          return Container(
                            alignment: Alignment.centerRight,
                            constraints: const BoxConstraints(minWidth: 50),
                            child: Text(
                              item.value,
                            ),
                          );
                        }).toList(),
                        onChanged: settingsController.setAppLanguage,
                      ),
                    ),
                  ),
                  if (!isDesktop)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("playerUi".tr),
                      subtitle: Text("playerUiDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.playerUi.value,
                          items: [
                            DropdownMenuItem(
                                value: 0, child: Text("standard".tr)),
                            DropdownMenuItem(
                              value: 1,
                              child: Text("gesture".tr),
                            ),
                          ],
                          onChanged: settingsController.setPlayerUi,
                        ),
                      ),
                    ),
                  if (!isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("enableBottomNav".tr),
                        subtitle: Text("enableBottomNavDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController
                                  .isBottomNavBarEnabled.isTrue,
                              onChanged: settingsController.enableBottomNavBar),
                        )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("disableTransitionAnimation".tr),
                      subtitle: Text("disableTransitionAnimationDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value: settingsController
                                .isTransitionAnimationDisabled.isTrue,
                            onChanged:
                                settingsController.disableTransitionAnimation),
                      )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("enableSlidableAction".tr),
                      subtitle: Text("enableSlidableActionDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value:
                                settingsController.slidableActionEnabled.isTrue,
                            onChanged: settingsController.toggleSlidableAction),
                      )),
                ],
              ),
              CustomExpansionTile(
                  title: "content".tr,
                  icon: Icons.music_video,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("setDiscoverContent".tr),
                      subtitle: Obx(() => Text(
                          settingsController.discoverContentType.value == "QP"
                              ? "quickpicks".tr
                              : settingsController.discoverContentType.value ==
                                      "TMV"
                                  ? "topmusicvideos".tr
                                  : settingsController
                                              .discoverContentType.value ==
                                          "TR"
                                      ? "trending".tr
                                      : "basedOnLast".tr,
                          style: Theme.of(context).textTheme.bodyMedium)),
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) =>
                            const DiscoverContentSelectorDialog(),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("homeContentCount".tr),
                      subtitle: Text("homeContentCountDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.noOfHomeScreenContent.value,
                          items: ([3, 5, 7, 9, 11])
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text("$e")))
                              .toList(),
                          onChanged: settingsController.setContentNumber,
                        ),
                      ),
                    ),
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("cacheHomeScreenData".tr),
                        subtitle: Text("cacheHomeScreenDataDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value:
                                  settingsController.cacheHomeScreenData.value,
                              onChanged:
                                  settingsController.toggleCacheHomeScreenData),
                        )),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("Piped".tr),
                      subtitle: Text("linkPipedDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: TextButton(
                          child: Obx(() => Text(
                                settingsController.isLinkedWithPiped.value
                                    ? "unLink".tr
                                    : "link".tr,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium!
                                    .copyWith(fontSize: 15),
                              )),
                          onPressed: () {
                            if (settingsController.isLinkedWithPiped.isFalse) {
                              showDialog(
                                context: context,
                                builder: (context) => const LinkPiped(),
                              ).whenComplete(
                                  () => Get.delete<PipedLinkedController>());
                            } else {
                              settingsController.unlinkPiped();
                            }
                          }),
                    ),
                    Obx(() => (settingsController.isLinkedWithPiped.isTrue)
                        ? ListTile(
                            contentPadding: const EdgeInsets.only(
                                left: 5, right: 10, top: 0),
                            title: Text("resetblacklistedplaylist".tr),
                            subtitle: Text("resetblacklistedplaylistDes".tr,
                                style: Theme.of(context).textTheme.bodyMedium),
                            trailing: TextButton(
                                child: Text(
                                  "reset".tr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .copyWith(fontSize: 15),
                                ),
                                onPressed: () async {
                                  await Get.find<LibraryPlaylistsController>()
                                      .resetBlacklistedPlaylist();
                                  ScaffoldMessenger.of(Get.context!)
                                      .showSnackBar(snackbar(Get.context!,
                                          "blacklistPlstResetAlert".tr,
                                          size: SanckBarSize.MEDIUM));
                                }),
                          )
                        : const SizedBox.shrink()),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("clearImgCache".tr),
                      subtitle: Text(
                        "clearImgCacheDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () {
                        settingsController.clearImagesCache().then((value) =>
                            ScaffoldMessenger.of(Get.context!).showSnackBar(
                                snackbar(Get.context!, "clearImgCacheAlert".tr,
                                    size: SanckBarSize.BIG)));
                      },
                    ),
                  ]),
              CustomExpansionTile(
                title: "music&Playback".tr,
                icon: Icons.music_note,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("streamingQuality".tr),
                    subtitle: Text("streamingQualityDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => DropdownButton(
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox.shrink(),
                        value: settingsController.streamingQuality.value,
                        items: [
                          DropdownMenuItem(
                              value: AudioQuality.Low, child: Text("low".tr)),
                          DropdownMenuItem(
                            value: AudioQuality.High,
                            child: Text("high".tr),
                          ),
                        ],
                        onChanged: settingsController.setStreamingQuality,
                      ),
                    ),
                  ),
                  if (GetPlatform.isAndroid)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("loudnessNormalization".tr),
                        subtitle: Text("loudnessNormalizationDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController
                                  .loudnessNormalizationEnabled.value,
                              onChanged: settingsController
                                  .toggleLoudnessNormalization),
                        )),
                  if (!isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("cacheSongs".tr),
                        subtitle: Text("cacheSongsDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController.cacheSongs.value,
                              onChanged:
                                  settingsController.toggleCachingSongsValue),
                        )),
                  if (!isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("skipSilence".tr),
                        subtitle: Text("skipSilenceDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value:
                                  settingsController.skipSilenceEnabled.value,
                              onChanged: settingsController.toggleSkipSilence),
                        )),
                  if (isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("backgroundPlay".tr),
                        subtitle: Text("backgroundPlayDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController
                                  .backgroundPlayEnabled.value,
                              onChanged:
                                  settingsController.toggleBackgroundPlay),
                        )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("keepScreenOnWhilePlaying".tr),
                      subtitle: Text("keepScreenOnWhilePlayingDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value: settingsController.keepScreenAwake.value,
                            onChanged:
                                settingsController.toggleKeepScreenAwake),
                      )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("restoreLastPlaybackSession".tr),
                      subtitle: Text("restoreLastPlaybackSessionDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value:
                                settingsController.restorePlaybackSession.value,
                            onChanged: settingsController
                                .toggleRestorePlaybackSession),
                      )),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("autoOpenPlayer".tr),
                    subtitle: Text("autoOpenPlayerDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => CustSwitch(
                          value: settingsController.autoOpenPlayer.value,
                          onChanged: settingsController.toggleAutoOpenPlayer),
                    ),
                  ),
                  if (!isDesktop)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("equalizer".tr),
                      subtitle: Text("equalizerDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      onTap: () async {
                        try {
                          await Get.find<PlayerController>().openEqualizer();
                        } catch (e) {
                          printERROR(e);
                        }
                      },
                    ),
                  if (!isDesktop)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("stopMusicOnTaskClear".tr),
                      subtitle: Text("stopMusicOnTaskClearDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value: settingsController
                                .stopPlyabackOnSwipeAway.value,
                            onChanged: settingsController
                                .toggleStopPlyabackOnSwipeAway),
                      ),
                    ),
                  GetPlatform.isAndroid
                      ? Obx(
                          () => ListTile(
                            contentPadding:
                                const EdgeInsets.only(left: 5, right: 10),
                            title: Text("ignoreBatOpt".tr),
                            onTap: settingsController
                                    .isIgnoringBatteryOptimizations.isFalse
                                ? settingsController
                                    .enableIgnoringBatteryOptimizations
                                : null,
                            subtitle: Obx(() => RichText(
                                  text: TextSpan(
                                    text:
                                        "${"status".tr}: ${settingsController.isIgnoringBatteryOptimizations.isTrue ? "enabled".tr : "disabled".tr}\n",
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium!
                                        .copyWith(fontWeight: FontWeight.bold),
                                    children: <TextSpan>[
                                      TextSpan(
                                          text: "ignoreBatOptDes".tr,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium),
                                    ],
                                  ),
                                )),
                          ),
                        )
                      : const SizedBox.shrink(),
                ],
              ),
              CustomExpansionTile(
                title: "download".tr,
                icon: Icons.download,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("autoDownFavSong".tr),
                    subtitle: Text("autoDownFavSongDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => CustSwitch(
                          value: settingsController
                              .autoDownloadFavoriteSongEnabled.value,
                          onChanged: settingsController
                              .toggleAutoDownloadFavoriteSong),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("downloadingFormat".tr),
                    subtitle: Text("downloadingFormatDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => DropdownButton(
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox.shrink(),
                        value: settingsController.downloadingFormat.value,
                        items: const [
                          DropdownMenuItem(
                              value: "opus", child: Text("Opus/Ogg")),
                          DropdownMenuItem(
                            value: "m4a",
                            child: Text("M4a"),
                          ),
                        ],
                        onChanged: settingsController.changeDownloadingFormat,
                      ),
                    ),
                  ),
                  ListTile(
                    trailing: TextButton(
                      child: Text(
                        "reset".tr,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontSize: 15),
                      ),
                      onPressed: () {
                        settingsController.resetDownloadLocation();
                      },
                    ),
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10, top: 0),
                    title: Text("downloadLocation".tr),
                    subtitle: Obx(() => Text(
                        settingsController.isCurrentPathsupportDownDir
                            ? "In App storage directory"
                            : settingsController.downloadLocationPath.value,
                        style: Theme.of(context).textTheme.bodyMedium)),
                    onTap: () async {
                      settingsController.setDownloadLocation();
                    },
                  ),
                  if (GetPlatform.isAndroid)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("exportDowloadedFiles".tr),
                      subtitle: Text(
                        "exportDowloadedFilesDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const ExportFileDialog(),
                      ).whenComplete(
                          () => Get.delete<ExportFileDialogController>()),
                    ),
                  if (GetPlatform.isAndroid)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("exportedFileLocation".tr),
                      subtitle: Obx(() => Text(
                          settingsController.exportLocationPath.value,
                          style: Theme.of(context).textTheme.bodyMedium)),
                      onTap: () async {
                        settingsController.setExportedLocation();
                      },
                    ),
                ],
              ),
              CustomExpansionTile(
                  title: "${"backup".tr} & ${"restore".tr}",
                  icon: Icons.restore,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("backupAppData".tr),
                      subtitle: Text(
                        "backupSettingsAndPlaylistsDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const BackupDialog(),
                      ).whenComplete(
                          () => Get.delete<BackupDialogController>()),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("restoreAppData".tr),
                      subtitle: Text(
                        "restoreSettingsAndPlaylistsDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const RestoreDialog(),
                      ).whenComplete(
                          () => Get.delete<RestoreDialogController>()),
                    ),
                  ]),
              CustomExpansionTile(
                  icon: Icons.miscellaneous_services,
                  title: "misc".tr,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("resetToDefault".tr),
                      subtitle: Text(
                        "resetToDefaultDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onTap: () {
                        settingsController
                            .resetAppSettingsToDefault()
                            .then((_) {
                          ScaffoldMessenger.of(Get.context!).showSnackBar(
                              snackbar(Get.context!, "resetToDefaultMsg".tr,
                                  size: SanckBarSize.BIG,
                                  duration: const Duration(seconds: 2)));
                        });
                      },
                    ),
                  ]),
              CustomExpansionTile(
                icon: Icons.graphic_eq,
                title: "riffFeatures".tr,
                children: [
                  Obx(() {
                    final connected = settingsController.ytConnected.value;
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10),
                      title: Text("ytAccount".tr),
                      subtitle: Text(
                          connected ? "ytConnectedDes".tr : "ytAccountDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Icon(connected ? Icons.link_off : Icons.login),
                      onTap: () async {
                        if (connected) {
                          await YtAuthService.disconnect();
                          settingsController.ytConnected.value = false;
                          Get.find<HomeScreenController>()
                              .loadContentFromNetwork();
                        } else {
                          final ok =
                              await Get.to(() => const YtLoginScreen());
                          if (ok == true) {
                            settingsController.ytConnected.value = true;
                            Get.find<HomeScreenController>()
                                .loadContentFromNetwork();
                            ScaffoldMessenger.of(Get.context!).showSnackBar(
                                snackbar(Get.context!, "ytConnectedMsg".tr,
                                    size: SanckBarSize.BIG,
                                    duration: const Duration(seconds: 3)));
                          }
                        }
                      },
                    );
                  }),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10),
                    title: Text("speedAndPitch".tr),
                    subtitle: Text("speedAndPitchDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    onTap: () => showDialog(
                        context: context,
                        builder: (context) => const SpeedPitchDialog()),
                  ),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10),
                    title: Text("stats".tr),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.toNamed(ScreenNavigationSetup.statsScreen,
                        id: ScreenNavigationSetup.id),
                  ),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10),
                    title: Text("riffRewind".tr),
                    subtitle: Text("riffRewindDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.toNamed(ScreenNavigationSetup.rewindScreen,
                        id: ScreenNavigationSetup.id),
                  ),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10),
                    title: Text("bannedSongs".tr),
                    subtitle: Text("neverPlayThisDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    onTap: () => showDialog(
                        context: context,
                        builder: (context) => const BannedSongsDialog()),
                  ),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10),
                    title: Text("listenBrainz".tr),
                    subtitle: Text("listenBrainzDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    onTap: () => showDialog(
                        context: context,
                        builder: (context) => const ListenBrainzDialog()),
                  ),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10),
                    title: Text("discoverySettings".tr),
                    subtitle: Text("discoverySettingsDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog(
                        context: context,
                        builder: (context) => const DiscoverySettingsDialog()),
                  ),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10),
                    title: Text("tasteModelDebug".tr),
                    subtitle: Text("tasteModelDebugDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    onTap: () => showDialog(
                        context: context,
                        builder: (context) => const TasteModelDebugDialog()),
                  ),
                ],
              ),
              CustomExpansionTile(
                icon: Icons.info,
                title: "appInfo".tr,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("github".tr),
                    subtitle: Text(
                      "${"githubDes".tr}${((Get.find<PlayerController>().playerPanelMinHeight.value) == 0 || !isBottomNavActive) ? "" : "\n\n${settingsController.currentVersion}"}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    isThreeLine: true,
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          'https://github.com/Aimdi/Riff-mobile',
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                  const Divider(),
                  SizedBox(
                    child: Column(
                      children: [
                        Text(
                          "Riff",
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(settingsController.currentVersion,
                            style: Theme.of(context).textTheme.titleMedium)
                      ],
                    ),
                  ),
                ],
              )
            ],
          )),
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Text(
              "${settingsController.currentVersion} — based on Harmony Music ${"by".tr} anandnet",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeSelectorDialog extends StatelessWidget {
  const ThemeSelectorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 300,
        //color: Theme.of(context).cardColor,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "themeMode".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          radioWidget(
            label: "dynamic".tr,
            controller: settingsController,
            value: ThemeType.dynamic,
          ),
          radioWidget(
              label: "systemDefault".tr,
              controller: settingsController,
              value: ThemeType.system),
          radioWidget(
              label: "dark".tr,
              controller: settingsController,
              value: ThemeType.dark),
          radioWidget(
              label: "light".tr,
              controller: settingsController,
              value: ThemeType.light),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 10, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Accent",
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 5),
            child: Obx(() {
              final themeController = Get.find<ThemeController>();
              final current = themeController.accentColor.value;
              return Row(
                children: ThemeController.riffAccents.entries
                    .map((entry) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                themeController.changeAccentColor(entry.value),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: entry.value,
                                shape: BoxShape.circle,
                              ),
                              child: current.value == entry.value.value
                                  ? const Icon(Icons.check,
                                      size: 18, color: Colors.black)
                                  : null,
                            ),
                          ),
                        ))
                    .toList(),
              );
            }),
          ),
          Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ))
        ]),
      ),
    );
  }
}

class DiscoverContentSelectorDialog extends StatelessWidget {
  const DiscoverContentSelectorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 300,
        //color: Theme.of(context).cardColor,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "setDiscoverContent".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          SizedBox(
            height: 180,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  radioWidget(
                      label: "quickpicks".tr,
                      controller: settingsController,
                      value: "QP"),
                  radioWidget(
                      label: "topmusicvideos".tr,
                      controller: settingsController,
                      value: "TMV"),
                  radioWidget(
                      label: "trending".tr,
                      controller: settingsController,
                      value: "TR"),
                  radioWidget(
                      label: "basedOnLast".tr,
                      controller: settingsController,
                      value: "BOLI"),
                ],
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
          Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ))
        ]),
      ),
    );
  }
}

Widget radioWidget(
    {required String label,
    required SettingsScreenController controller,
    required value}) {
  return Obx(() => ListTile(
        visualDensity: const VisualDensity(vertical: -4),
        onTap: () {
          if (value.runtimeType == ThemeType) {
            controller.onThemeChange(value);
          } else {
            controller.onContentChange(value);
            Navigator.of(Get.context!).pop();
          }
        },
        leading: Radio(
            value: value,
            groupValue: value.runtimeType == ThemeType
                ? controller.themeModetype.value
                : controller.discoverContentType.value,
            onChanged: value.runtimeType == ThemeType
                ? controller.onThemeChange
                : controller.onContentChange),
        title: Text(label),
      ));
}

/// Manage the "Never Play This" list: shows banned songs with an
/// unban action for each.
class BannedSongsDialog extends StatefulWidget {
  const BannedSongsDialog({super.key});

  @override
  State<BannedSongsDialog> createState() => _BannedSongsDialogState();
}

class _BannedSongsDialogState extends State<BannedSongsDialog> {
  @override
  Widget build(BuildContext context) {
    final banned = BanService.all;
    final bannedArtists = BanService.allArtists;
    final bannedCollections = BanService.allCollections;
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text("bannedSongs".tr,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (banned.isEmpty &&
                bannedArtists.isEmpty &&
                bannedCollections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(15),
                child: Text("noBannedSongs".tr,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...bannedCollections.map((c) => ListTile(
                        visualDensity: const VisualDensity(vertical: -3),
                        leading: Icon(
                            c["type"] == "album"
                                ? Icons.album
                                : Icons.playlist_play,
                            size: 20),
                        title: Text(c["title"], maxLines: 1),
                        subtitle: Text("bannedCollectionTag".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            BanService.unbanCollection(c["id"]);
                            setState(() {});
                          },
                        ),
                      )),
                  ...bannedArtists.map((artist) => ListTile(
                        visualDensity: const VisualDensity(vertical: -3),
                        leading: const Icon(Icons.person_off, size: 20),
                        title: Text(artist["name"], maxLines: 1),
                        subtitle: Text("bannedArtistTag".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            BanService.unbanArtist(artist["key"]);
                            setState(() {});
                          },
                        ),
                      )),
                  ...banned.map((song) => ListTile(
                        visualDensity: const VisualDensity(vertical: -3),
                        title: Text(song["title"], maxLines: 1),
                        subtitle: Text(song["artist"], maxLines: 1),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            BanService.unban(song["id"]);
                            setState(() {});
                          },
                        ),
                      )),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20, top: 5),
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text("cancel".tr),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ListenBrainz token entry; an empty token disables scrobbling.
class ListenBrainzDialog extends StatefulWidget {
  const ListenBrainzDialog({super.key});

  @override
  State<ListenBrainzDialog> createState() => _ListenBrainzDialogState();
}

class _ListenBrainzDialogState extends State<ListenBrainzDialog> {
  late final TextEditingController textController;

  @override
  void initState() {
    super.initState();
    textController = TextEditingController(text: ListenBrainzService.token);
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("listenBrainz".tr,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text("listenBrainzDes".tr,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 15),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                hintText: "ListenBrainz user token",
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text("cancel".tr),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () {
                    ListenBrainzService.setToken(textController.text);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text("confirm".tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Discovery preferences (Settings → Riff → Discovery).
class DiscoverySettingsDialog extends StatefulWidget {
  const DiscoverySettingsDialog({super.key});

  @override
  State<DiscoverySettingsDialog> createState() =>
      _DiscoverySettingsDialogState();
}

class _DiscoverySettingsDialogState extends State<DiscoverySettingsDialog> {
  late double exploration;
  late bool wifiOnly;
  late int mixCount;
  late bool unheardOnly;
  late bool lbRecs;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<DiscoveryService>()) {
      final d = Get.find<DiscoveryService>();
      exploration = d.exploration;
      wifiOnly = d.wifiOnlyGeneration;
      mixCount = d.mixCount;
      unheardOnly = d.unheardOnlyDefault;
      lbRecs = d.listenBrainzRecs;
    } else {
      exploration = 0.5;
      wifiOnly = true;
      mixCount = 4;
      unheardOnly = false;
      lbRecs = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Container(
        height: 460,
        padding:
            const EdgeInsets.only(top: 20, bottom: 10, left: 20, right: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("discoverySettings".tr,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
                "${"exploration".tr}: ${exploration < 0.33 ? "familiar".tr : exploration > 0.66 ? "adventurous".tr : "balanced".tr}"),
            Slider(
              value: exploration,
              onChanged: (v) => setState(() => exploration = v),
              min: 0,
              max: 1,
              divisions: 10,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("mixCount".tr),
                DropdownButton<int>(
                  value: mixCount,
                  items: [3, 4, 5]
                      .map((e) => DropdownMenuItem(value: e, child: Text("$e")))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => mixCount = v);
                  },
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("wifiOnlyGeneration".tr),
              value: wifiOnly,
              onChanged: (v) => setState(() => wifiOnly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("unheardOnly".tr),
              value: unheardOnly,
              onChanged: (v) => setState(() => unheardOnly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("listenBrainzRecs".tr),
              value: lbRecs,
              onChanged: (v) => setState(() => lbRecs = v),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () async {
                    if (Get.isRegistered<DiscoveryService>()) {
                      await Get.find<DiscoveryService>().resetTasteModel();
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                          context, "tasteModelReset".tr,
                          size: SanckBarSize.MEDIUM));
                    }
                  },
                  child: Text("resetTasteModel".tr),
                ),
                TextButton(
                  onPressed: () {
                    if (Get.isRegistered<DiscoveryService>()) {
                      final d = Get.find<DiscoveryService>();
                      d.exploration = exploration;
                      d.wifiOnlyGeneration = wifiOnly;
                      d.mixCount = mixCount;
                      d.unheardOnlyDefault = unheardOnly;
                      d.listenBrainzRecs = lbRecs;
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text("confirm".tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Temporary debug page for affinity / skip-rate inspection.
class TasteModelDebugDialog extends StatelessWidget {
  const TasteModelDebugDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final snap = Get.isRegistered<DiscoveryService>()
        ? Get.find<DiscoveryService>().debugSnapshot()
        : <String, dynamic>{};
    final artists = (snap['artists'] as List?) ?? [];
    return CommonDialog(
      child: Container(
        height: 480,
        padding:
            const EdgeInsets.only(top: 20, bottom: 10, left: 16, right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("tasteModelDebug".tr,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              "events: ${snap['eventCount'] ?? 0} · tracks: ${snap['trackStatsCount'] ?? 0} · edges: ${snap['coocEdges'] ?? 0}",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(),
            Expanded(
              child: artists.isEmpty
                  ? Center(child: Text("statsEmpty".tr))
                  : ListView.builder(
                      itemCount: artists.length,
                      itemBuilder: (context, i) {
                        final a = artists[i] as Map;
                        return ListTile(
                          dense: true,
                          title: Text("${a['key']}"),
                          subtitle: Text(
                              "score ${a['score']} · skip ${(a['skipRate'] as num) * 100}%"),
                        );
                      },
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text("cancel".tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Playback speed and pitch controls (RiPlay-style). Persisted and
/// applied live to the running player.
class SpeedPitchDialog extends StatefulWidget {
  const SpeedPitchDialog({super.key});

  @override
  State<SpeedPitchDialog> createState() => _SpeedPitchDialogState();
}

class _SpeedPitchDialogState extends State<SpeedPitchDialog> {
  final settings = Get.find<SettingsScreenController>();
  late double speed = settings.playbackSpeed.value;
  late double pitch = settings.playbackPitch.value;
  late double bass = settings.bassBoost.value.toDouble();
  late double volumeBoost = settings.volumeBoostMb.value.toDouble();
  late int reverb = settings.reverbPreset.value;
  late double virtualizer = settings.virtualizer.value.toDouble();

  static const _reverbNames = [
    "reverbOff",
    "reverbSmallRoom",
    "reverbMediumRoom",
    "reverbLargeRoom",
    "reverbMediumHall",
    "reverbLargeHall",
    "reverbPlate",
  ];

  void _apply() {
    settings.setBox.put("playbackSpeed", speed);
    settings.setBox.put("playbackPitch", pitch);
    settings.playbackSpeed.value = speed;
    settings.playbackPitch.value = pitch;
    Get.find<PlayerController>()
        .setSpeedAndPitch(speed: speed, pitch: pitch);
  }

  void _applyFx() {
    settings.setBox.put("bassBoost", bass.round());
    settings.setBox.put("volumeBoostMb", volumeBoost.round());
    settings.setBox.put("reverbPreset", reverb);
    settings.setBox.put("virtualizer", virtualizer.round());
    settings.bassBoost.value = bass.round();
    settings.volumeBoostMb.value = volumeBoost.round();
    settings.reverbPreset.value = reverb;
    settings.virtualizer.value = virtualizer.round();
    Get.find<PlayerController>().applyAudioFx();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("speedAndPitch".tr,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 15),
              Text("${"speed".tr}: ${speed.toStringAsFixed(2)}x"),
              Slider(
                min: 0.5,
                max: 2.0,
                divisions: 30,
                value: speed,
                label: "${speed.toStringAsFixed(2)}x",
                onChanged: (v) => setState(() => speed = v),
                onChangeEnd: (_) => _apply(),
              ),
              Text("${"pitch".tr}: ${pitch.toStringAsFixed(2)}"),
              Slider(
                min: 0.5,
                max: 1.5,
                divisions: 20,
                value: pitch,
                label: pitch.toStringAsFixed(2),
                onChanged: (v) => setState(() => pitch = v),
                onChangeEnd: (_) => _apply(),
              ),
              Text("${"bassBoost".tr}: ${(bass / 10).round()}%"),
              Slider(
                min: 0,
                max: 1000,
                divisions: 20,
                value: bass,
                label: "${(bass / 10).round()}%",
                onChanged: (v) => setState(() => bass = v),
                onChangeEnd: (_) => _applyFx(),
              ),
              Text("${"volumeBoost".tr}: +${(volumeBoost / 100).toStringAsFixed(1)} dB"),
              Slider(
                min: 0,
                max: 2000,
                divisions: 20,
                value: volumeBoost,
                label: "+${(volumeBoost / 100).toStringAsFixed(1)} dB",
                onChanged: (v) => setState(() => volumeBoost = v),
                onChangeEnd: (_) => _applyFx(),
              ),
              Text("${"stereoWidth".tr}: ${(virtualizer / 10).round()}%"),
              Slider(
                min: 0,
                max: 1000,
                divisions: 20,
                value: virtualizer,
                label: "${(virtualizer / 10).round()}%",
                onChanged: (v) => setState(() => virtualizer = v),
                onChangeEnd: (_) => _applyFx(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text("${"reverb".tr}:  "),
                    DropdownButton<int>(
                      value: reverb,
                      dropdownColor: Theme.of(context).cardColor,
                      underline: const SizedBox.shrink(),
                      items: List.generate(
                          _reverbNames.length,
                          (i) => DropdownMenuItem(
                              value: i, child: Text(_reverbNames[i].tr))),
                      onChanged: (v) {
                        setState(() => reverb = v ?? 0);
                        _applyFx();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        speed = 1.0;
                        pitch = 1.0;
                        bass = 0;
                        volumeBoost = 0;
                        reverb = 0;
                        virtualizer = 0;
                      });
                      _apply();
                      _applyFx();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text("resetToDefault".tr),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text("done".tr),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
