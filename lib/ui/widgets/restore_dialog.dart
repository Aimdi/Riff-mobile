import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '../../services/permission_service.dart';
import '/ui/theme/riff_spacing.dart';
import 'common_dialog_widget.dart';

class RestoreDialog extends StatelessWidget {
  const RestoreDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(RestoreDialogController());
    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.only(
            left: RiffSpacing.xxl,
            top: RiffSpacing.xxl,
            right: RiffSpacing.xxl,
            bottom: RiffSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RiffDialogTitle("restoreAppData".tr,
                icon: Icons.settings_backup_restore_rounded),
            SizedBox(
              height: 120,
              child: Center(
                child: Obx(() {
                  final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface);
                  if (c.restoreProgress.toInt() == c.filesToRestore.toInt()) {
                    return Text("restoreMsg".tr,
                        textAlign: TextAlign.center, style: style);
                  }
                  if (c.processingFiles.isTrue) {
                    return Text("processFiles".tr, style: style);
                  }
                  if (c.restoreRunning.isTrue) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            "${c.restoreProgress.toInt()}/${c.filesToRestore.toInt()}",
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary)),
                        const SizedBox(height: RiffSpacing.xs),
                        Text("restoring".tr, style: style),
                      ],
                    );
                  }
                  return Text("letsStrart".tr,
                      textAlign: TextAlign.center, style: style);
                }),
              ),
            ),
            Obx(() {
              final done =
                  c.restoreProgress.toInt() == c.filesToRestore.toInt();
              return RiffDialogButton(
                done ? "restartApp".tr : "restore".tr,
                onPressed: c.processingFiles.isTrue || c.restoreRunning.isTrue
                    ? null
                    : () {
                        if (done) {
                          GetPlatform.isAndroid
                              ? TerminateRestart.instance.restartApp(
                                  options: const TerminateRestartOptions(
                                    terminate: true,
                                  ),
                                )
                              : exit(0);
                        } else {
                          c.restore();
                        }
                      },
              );
            }),
          ],
        ),
      ),
    );
  }
}

class RestoreDialogController extends GetxController {
  final restoreRunning = false.obs;
  final restoreProgress = (-1).obs;
  final filesToRestore = (0).obs;
  final processingFiles = false.obs;

  Future<void> restore() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final FilePickerResult? pickedFileResult = await FilePicker.platform
        .pickFiles(
            dialogTitle: "Select backup file",
            type: GetPlatform.isWindows ? FileType.custom : FileType.any,
            allowedExtensions: GetPlatform.isWindows ? ['hmb'] : null,
            allowMultiple: false);

    final String? pickedFile = pickedFileResult?.files.first.path;

    // is this check necessary?
    if (pickedFile == '/' || pickedFile == null) {
      return;
    }
    processingFiles.value = true;
    await Future.delayed(const Duration(seconds: 4));
    final restoreFilePath = pickedFile.toString();
    final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;
    final dbDirPath = await Get.find<SettingsScreenController>().dbDir;
    final Directory dbDir = Directory(dbDirPath);
    printInfo(info: dbDir.path);
    await Get.find<SettingsScreenController>().closeAllDatabases();

    //delele all the files with extension .hive
    for (final file in dbDir.listSync()) {
      if (file is File && file.path.endsWith('.hive')) {
        await file.delete();
      }
    }
    final bytes = await File(restoreFilePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    filesToRestore.value = archive.length;
    restoreProgress.value = 0;
    processingFiles.value = false;
    restoreRunning.value = true;
    for (final file in archive) {
      final filename = file.name;
      printINFO(filename);
      if (file.isFile) {
        final data = file.content as List<int>;
        final targetFileDir =
            filename.endsWith(".m4a") || filename.endsWith(".opus")
                ? "$supportDirPath/Music"
                : filename.endsWith(".png")
                    ? "$supportDirPath/thumbnails"
                    : dbDirPath;
        final outputFile = File('$targetFileDir/$filename');
        await outputFile.create(recursive: true);
        await outputFile.writeAsBytes(data);
        restoreProgress.value++;
      }
    }
    // Clear file picker temp directory
    final tempFilePickerDirPath =
        "${(await getApplicationCacheDirectory()).path}/file_picker";
    final tempFilePickerDir = Directory(tempFilePickerDirPath);
    if (tempFilePickerDir.existsSync()) {
      await tempFilePickerDir.delete(recursive: true);
    }

    // change file download path to support dir path in songs if system is windows or linux
    if (GetPlatform.isWindows || GetPlatform.isLinux) {
      // open the restored box
      final newSongBox = await Hive.openBox("SongDownloads");
      final downloadedSongs = newSongBox.values.toList();
      for (final song in downloadedSongs) {
        final songPath = song["url"];
        if (songPath != null && songPath is String) {
          final fileName = songPath.split("/").last;
          final newFilePath = "$supportDirPath/Music/$fileName";
          song["url"] = newFilePath;
          song['streamInfo'][1]['url'] = newFilePath;
          await newSongBox.put(song["videoId"], song);
        }
      }
    }

    restoreRunning.value = false;
  }
}
