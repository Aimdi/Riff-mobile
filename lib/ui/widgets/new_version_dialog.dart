import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/Home/home_screen_controller.dart';
import 'common_dialog_widget.dart';

class NewVersionDialog extends StatelessWidget {
  const NewVersionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RiffDialogTitle("newVersionAvailable".tr,
                icon: Icons.system_update_rounded),
            const SizedBox(height: 20),
            RiffDialogButton(
              "download".tr,
              onPressed: () {
                launchUrl(
                  Uri.parse(
                    'https://github.com/Aimdi/Riff-mobile/releases/latest',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            const SizedBox(height: 4),
            GetX<HomeScreenController>(
                builder: (controller) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: Theme.of(context).colorScheme.secondary,
                      checkColor: Colors.black,
                      title: Text("dontShowInfoAgain".tr,
                          style: const TextStyle(fontSize: 14)),
                      value: controller.showVersionDialog.isFalse,
                      onChanged: (val) =>
                          controller.onChangeVersionVisibility(val ?? false),
                    )),
            RiffDialogButton("dismiss".tr,
                primary: false, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
