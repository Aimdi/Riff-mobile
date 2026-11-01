import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/loader.dart';
import '/utils/helper.dart';
import '../../services/permission_service.dart';
import '/ui/theme/riff_spacing.dart';
import 'common_dialog_widget.dart';

class BackupDialog extends StatelessWidget {
  const BackupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(BackupDialogController());
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
            RiffDialogTitle("backupAppData".tr, icon: Icons.backup_outlined),
            SizedBox(
              height: 110,
              child: Center(
                child: Obx(() {
                  final busy = c.scanning.isTrue || c.backupRunning.isTrue;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) ...[
                        const LoadingIndicator(),
                        const SizedBox(height: RiffSpacing.sm),
                      ],
                      Text(
                        c.scanning.isTrue
                            ? "scanning".tr
                            : c.backupRunning.isTrue
                                ? "backupInProgress".tr
                                : c.isbackupCompleted.isTrue
                                    ? "backupMsg".tr
                                    : c.failed.isTrue
                                        ? "operationFailed".tr
                                        : "letsStrart".tr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      if (GetPlatform.isAndroid &&
                          c.isDownloadedfilesSeclected.isTrue) ...[
                        const SizedBox(height: RiffSpacing.sm),
                        Text("androidBackupWarning".tr,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface)),
                      ],
                    ],
                  );
                }),
              ),
            ),
            if (!GetPlatform.isDesktop)
              Obx(() => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text("includeDownloadedFiles".tr,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface)),
                    value: c.isDownloadedfilesSeclected.value,
                    onChanged: c.scanning.isTrue ||
                            c.backupRunning.isTrue ||
                            c.isbackupCompleted.isTrue
                        ? null
                        : (v) => c.isDownloadedfilesSeclected.value = v!,
                  )),
            const SizedBox(height: RiffSpacing.sm),
            Obx(() => RiffDialogButton(
                  c.isbackupCompleted.isTrue ? "close".tr : "backup".tr,
                  onPressed: c.backupRunning.isTrue || c.scanning.isTrue
                      ? null
                      : () {
                          if (c.isbackupCompleted.isTrue) {
                            Navigator.of(context).pop();
                          } else {
                            c.backup();
                          }
                        },
                )),
          ],
        ),
      ),
    );
  }
}

class BackupDialogController extends GetxController {
  final scanning = false.obs;
  final isbackupCompleted = false.obs;
  final backupRunning = false.obs;
  final isDownloadedfilesSeclected = false.obs;

  /// The backup couldn't be written (a folder Riff may not write to).
  final failed = false.obs;
  List<String> filesToExport = [];
  final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;

  Future<void> scanFilesToBackup() async {
    final dbDir = await Get.find<SettingsScreenController>().dbDir;
    filesToExport.addAll(await processDirectoryInIsolate(dbDir));
    if (isDownloadedfilesSeclected.value) {
      final downlodedSongFilePaths = [
        for (final data in Hive.box("SongDownloads").values)
          if (data is Map && data['url'] is String) data['url'] as String
      ];
      filesToExport.addAll(downlodedSongFilePaths);
      try {
        filesToExport.addAll(await processDirectoryInIsolate(
            "$supportDirPath/thumbnails",
            extensionFilter: ".png"));
      } catch (e) {
        printERROR(e);
      }
    }
  }

  Future<void> backup() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select backup file folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    scanning.value = true;
    await Future.delayed(const Duration(seconds: 4));
    await scanFilesToBackup();
    scanning.value = false;

    backupRunning.value = true;
    final exportDirPath = pickedFolderPath.toString();

    final backupPath =
        '$exportDirPath/${DateTime.now().millisecondsSinceEpoch.toString()}.hmb';
    compressFilesInBackground(filesToExport, backupPath).then((_) {
      backupRunning.value = false;
      isbackupCompleted.value = true;
    }).catchError((e) {
      printERROR('Error during compression: $e');
      // Said, not left on "Backup in progress"; and no half-written file
      // that a restore would later take for a backup.
      backupRunning.value = false;
      failed.value = true;
      try {
        final partial = File(backupPath);
        if (partial.existsSync()) partial.deleteSync();
      } catch (_) {}
    });
  }
}

/// Each file's name (without its folder) with its bytes. One that can't
/// be read (a download deleted meanwhile) is left out, name and all: the
/// names were kept, so every file after it was saved under the one
/// before's name (song B's audio as song A).
List<(String, List<int>)> filesForBackup(List<String> filePaths) {
  final files = <(String, List<int>)>[];
  for (final path in filePaths) {
    try {
      final data = File(path).readAsBytesSync();
      files.add((path.split(GetPlatform.isWindows ? '\\' : '/').last, data));
    } catch (e) {
      printERROR('Error reading file $path: $e');
    }
  }
  return files;
}

// Function to compress files (to be used with compute or isolate)
void _compressFiles(Map<String, dynamic> params) {
  final List<List<int>> filesData = params['filesData'];
  final List<String> fileNames = params['fileNames'];
  final String zipFilePath = params['zipFilePath'];

  final archive = Archive();

  for (int i = 0; i < filesData.length; i++) {
    final fileData = filesData[i];
    final fileName = fileNames[i];
    final file = ArchiveFile(fileName, fileData.length, fileData);
    archive.addFile(file);
  }

  final encoder = ZipEncoder();
  final zipFile = File(zipFilePath);
  zipFile.writeAsBytesSync(encoder.encode(archive)!);
}

// Example usage
Future<void> compressFilesInBackground(
    List<String> filePaths, String zipFilePath) async {
  final files = filesForBackup(filePaths);
  final List<List<int>> filesData = [for (final (_, d) in files) d];
  final List<String> fileNames = [for (final (n, _) in files) n];

  printINFO(fileNames);
  // Use compute to run the compression in the background
  await compute(_compressFiles, {
    'filesData': filesData,
    'fileNames': fileNames,
    'zipFilePath': zipFilePath,
  });
}

Future<List<String>> processDirectoryInIsolate(String dbDir,
    {String extensionFilter = ".hive"}) async {
  // Use Isolate.run to execute the function in a new isolate
  return await Isolate.run(() async {
    // List files in the directory
    final filesEntityList =
        await Directory(dbDir).list(recursive: false).toList();

    // Filter out .hive files
    final filesPath = filesEntityList
        .whereType<File>() // Ensure we only work with files
        .map((entity) {
          if (entity.path.endsWith(extensionFilter)) return entity.path;
        })
        .whereType<String>()
        .toList();

    return filesPath;
  });
}
