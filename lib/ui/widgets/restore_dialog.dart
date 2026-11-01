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
    // Restoring, or restored and waiting for the restart: the app's data is
    // closed, so the dialog stays until the app restarts.
    return Obx(() => PopScope(canPop: !c.locked, child: _dialog(context, c)));
  }

  Widget _dialog(BuildContext context, RestoreDialogController c) {
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
                  if (c.failed.isTrue) {
                    return Text("operationFailed".tr,
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

  /// The file picked couldn't be restored (not a Riff backup, cut short):
  /// nothing on the phone was changed.
  final failed = false.obs;

  /// Restoring, or restored and waiting for the restart: the app's data is
  /// closed meanwhile, so the dialog can't be left.
  bool get locked =>
      processingFiles.isTrue ||
      restoreRunning.isTrue ||
      restoreProgress.value == filesToRestore.value;

  Future<void> restore() async {
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
    failed.value = false;
    processingFiles.value = true;
    final restoreFilePath = pickedFile.toString();
    final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;
    final dbDirPath = await Get.find<SettingsScreenController>().dbDir;
    final Directory dbDir = Directory(dbDirPath);
    printInfo(info: dbDir.path);

    // Read and check the backup before anything is deleted: a wrong or
    // cut-short file used to wipe every list, playlist and setting first,
    // then fail with nothing to put back.
    List<ArchiveFile> files;
    try {
      final bytes = await File(restoreFilePath).readAsBytes();
      files = backupFilesToRestore(ZipDecoder().decodeBytes(bytes));
    } catch (e) {
      printERROR('Not a backup that can be restored: $e');
      files = const [];
    }
    if (files.isEmpty) {
      processingFiles.value = false;
      failed.value = true;
      return;
    }

    await Get.find<SettingsScreenController>().closeAllDatabases();

    //delele all the files with extension .hive
    for (final file in dbDir.listSync()) {
      if (file is File && file.path.endsWith('.hive')) {
        await file.delete();
      }
    }
    filesToRestore.value = files.length;
    restoreProgress.value = 0;
    processingFiles.value = false;
    restoreRunning.value = true;
    final restoredSongs = <String>{};
    for (final file in files) {
      final filename = file.name;
      printINFO(filename);
      final data = file.content as List<int>;
      final isSong = filename.endsWith(".m4a") || filename.endsWith(".opus");
      final targetFileDir = isSong
          ? "$supportDirPath/Music"
          : filename.endsWith(".png")
              ? "$supportDirPath/thumbnails"
              : dbDirPath;
      final outputFile = File('$targetFileDir/$filename');
      await outputFile.create(recursive: true);
      await outputFile.writeAsBytes(data);
      if (isSong) restoredSongs.add(filename);
      restoreProgress.value++;
    }
    // Clear file picker temp directory
    final tempFilePickerDirPath =
        "${(await getApplicationCacheDirectory()).path}/file_picker";
    final tempFilePickerDir = Directory(tempFilePickerDirPath);
    if (tempFilePickerDir.existsSync()) {
      await tempFilePickerDir.delete(recursive: true);
    }

    // Downloaded songs restored with the backup are where it put them: their
    // paths (another phone's folder, a desktop's) point there now. Only
    // Windows and Linux used to, so on Android they streamed instead.
    if (restoredSongs.isNotEmpty) {
      final newSongBox = await Hive.openBox("SongDownloads");
      for (final song in newSongBox.values.toList()) {
        if (song is! Map) continue;
        final songPath = song["url"];
        if (songPath is! String) continue;
        final fileName = songPath.split(RegExp(r'[/\\]')).last;
        if (!restoredSongs.contains(fileName)) continue;
        final newFilePath = "$supportDirPath/Music/$fileName";
        song["url"] = newFilePath;
        final streamInfo = song['streamInfo'];
        if (streamInfo is List &&
            streamInfo.length > 1 &&
            streamInfo[1] is Map) {
          streamInfo[1]['url'] = newFilePath;
        }
        await newSongBox.put(song["videoId"], song);
      }
    }

    restoreRunning.value = false;
  }
}

/// What a backup restores: its app data (`.hive`), downloaded songs and
/// covers, each by its own name only. Empty when it isn't a Riff backup
/// (no settings in it, or a file of another kind).
List<ArchiveFile> backupFilesToRestore(Archive archive) {
  const kinds = ['.hive', '.m4a', '.opus', '.png'];
  final files = <ArchiveFile>[];
  for (final f in archive) {
    if (!f.isFile) continue;
    final name = f.name;
    if (name.contains('/') || name.contains('\\') || name.startsWith('.')) {
      return const [];
    }
    if (!kinds.any(name.toLowerCase().endsWith)) return const [];
    files.add(f);
  }
  final hasSettings = files.any((f) => f.name.toLowerCase() == 'appprefs.hive');
  return hasSettings ? files : const [];
}
