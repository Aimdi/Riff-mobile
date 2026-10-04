import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';

import '../../services/permission_service.dart';
import '/ui/theme/riff_spacing.dart';
import 'common_dialog_widget.dart';

class ExportFileDialog extends StatelessWidget {
  const ExportFileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ExportFileDialogController());
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
            RiffDialogTitle("exportDowloadedFiles".tr,
                icon: Icons.drive_file_move_outline),
            SizedBox(
              height: 120,
              child: Center(
                child: Obx(() {
                  final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface);
                  if (c.exportProgress.toInt() == c.filesToExport.length) {
                    return Text("exportMsg".tr,
                        textAlign: TextAlign.center, style: style);
                  }
                  if (c.exportRunning.isTrue) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            "${c.exportProgress.toInt()}/${c.filesToExport.length}",
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary)),
                        const SizedBox(height: RiffSpacing.xs),
                        Text("exporting".tr, style: style),
                      ],
                    );
                  }
                  if (c.ready.isTrue) {
                    return Text(
                        "${c.filesToExport.length} ${"downFilesFound".tr}",
                        textAlign: TextAlign.center,
                        style: style);
                  }
                  if (c.scanning.isTrue) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LoadingIndicator(),
                        const SizedBox(height: RiffSpacing.sm),
                        Text("scanning".tr, style: style),
                      ],
                    );
                  }
                  return const SizedBox();
                }),
              ),
            ),
            Obx(() {
              final done = c.exportProgress.toInt() == c.filesToExport.length;
              return RiffDialogButton(
                done ? "close".tr : "export".tr,
                onPressed: c.exportRunning.isTrue
                    ? null
                    : () {
                        if (done) {
                          Navigator.of(context).pop();
                        } else {
                          c.export();
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

class ExportFileDialogController extends GetxController {
  final scanning = true.obs;
  final ready = false.obs;
  final exportRunning = false.obs;
  final exportProgress = (-1).obs;
  List<String> filesToExport = [];

  @override
  void onInit() {
    scanFilesToExport();
    super.onInit();
  }

  Future<void> scanFilesToExport() async {
    final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;
    final filesEntityList =
        Directory("$supportDirPath/Music").listSync(recursive: false);
    final filesPath = filesEntityList.map((entity) => entity.path).toList();
    filesToExport.addAll(filesPath);
    scanning.value = false;
    ready.value = true;
  }

  Future<void> export() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    exportProgress.value = 0;
    exportRunning.value = true;
    final exportDirPath =
        Get.find<SettingsScreenController>().exportLocationPath.toString();
    final length_ = filesToExport.length;
    for (int i = 0; i < length_; i++) {
      final filePath = filesToExport[i];
      final newFilePath = "$exportDirPath/${filePath.split("/").last}";
      await File(filePath).copy(newFilePath);
      exportProgress.value = i + 1;
    }
    exportRunning.value = false;
  }
}
