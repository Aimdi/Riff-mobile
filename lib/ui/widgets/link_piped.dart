import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/helper.dart';
import '/services/piped_service.dart';
import '../screens/Settings/settings_screen_controller.dart';
import '../screens/Library/library_controller.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';
import 'snackbar.dart';

class LinkPiped extends StatelessWidget {
  const LinkPiped({super.key});

  @override
  Widget build(BuildContext context) {
    final pipedLinkedController = Get.put(PipedLinkedController());
    return CommonDialog(
        child: Obx(() => Container(
              height: pipedLinkedController.selectedInst.value == "custom"
                  ? 470
                  : 435,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RiffDialogTitle("Piped".tr, icon: Icons.link_rounded),
                  Padding(
                    padding: const EdgeInsets.only(top: 15.0, bottom: 10),
                    child: Obx(() => DropdownButton(
                        underline: const SizedBox.shrink(),
                        value: pipedLinkedController.selectedInst.value,
                        items: pipedLinkedController.pipedInstList
                            .map(
                              (element) => DropdownMenuItem(
                                  value: element.apiUrl,
                                  child: Text(element.name)),
                            )
                            .toList(),
                        onChanged: (val) {
                          pipedLinkedController.errorText.value = "";
                          pipedLinkedController.selectedInst.value =
                              val as String;
                        })),
                  ),
                  Obx(() => pipedLinkedController.selectedInst.value == "custom"
                      ? ModifiedTextField(
                          controller:
                              pipedLinkedController.instApiUrlInputController,
                          cursorColor:
                              Theme.of(context).textTheme.titleSmall!.color,
                          decoration:
                              InputDecoration(hintText: "hintApiUrl".tr))
                      : const SizedBox.shrink()),
                  ModifiedTextField(
                      controller: pipedLinkedController.usernameInputController,
                      cursorColor:
                          Theme.of(context).textTheme.titleSmall!.color,
                      decoration: InputDecoration(hintText: "username".tr)),
                  const SizedBox(
                    height: 15,
                  ),
                  Obx(() => ModifiedTextField(
                        controller:
                            pipedLinkedController.passwordInputController,
                        cursorColor:
                            Theme.of(context).textTheme.titleSmall!.color,
                        decoration: InputDecoration(
                          hintText: "password".tr,
                          suffixIcon: IconButton(
                            color:
                                Theme.of(context).textTheme.titleSmall!.color,
                            icon: pipedLinkedController.passwordVisible.value
                                ? const Icon(Icons.visibility_off)
                                : const Icon(Icons.visibility),
                            onPressed: () => pipedLinkedController
                                    .passwordVisible.value =
                                !pipedLinkedController.passwordVisible.value,
                          ),
                        ),
                        obscureText:
                            !pipedLinkedController.passwordVisible.value,
                      )),
                  Expanded(
                      child: Obx(() => Center(
                              child: Text(
                            pipedLinkedController.errorText.value,
                            textAlign: TextAlign.center,
                          )))),
                  RiffDialogButton("link".tr,
                      onPressed: pipedLinkedController.link),
                ],
              ),
            )));
  }
}

class PipedLinkedController extends GetxController {
  final instApiUrlInputController = TextEditingController();
  final usernameInputController = TextEditingController();
  final passwordInputController = TextEditingController();
  final pipedInstList =
      <PipedInstance>[PipedInstance(name: "selectAuthIns".tr, apiUrl: "")].obs;
  final selectedInst = "".obs;
  final _pipedServices = Get.find<PipedServices>();
  final passwordVisible = false.obs;
  final errorText = "".obs;

  @override
  void onInit() {
    getAllInstList();
    super.onInit();
  }

  Future<void> getAllInstList() async {
    _pipedServices.getAllInstanceList().then((res) {
      if (res.code == 1) {
        pipedInstList.addAll(List<PipedInstance>.from(res.response) +
            [PipedInstance(name: "customIns".tr, apiUrl: "custom")]);
      } else {
        errorText.value =
            "${res.errorMessage ?? "errorOccuredAlert".tr}! ${"customInsSelectMsg".tr}";
        pipedInstList
            .add(PipedInstance(name: "customIns".tr, apiUrl: "custom"));
      }
    });
  }

  void link() {
    errorText.value = "";
    final userName = usernameInputController.text;
    final password = passwordInputController.text;
    if (selectedInst.isEmpty) {
      errorText.value = "selectAuthInsMsg".tr;
      return;
    }
    if (userName.isEmpty ||
        password.isEmpty ||
        // ignore: invalid_use_of_protected_member
        (instApiUrlInputController.hasListeners &&
            instApiUrlInputController.text.isEmpty)) {
      errorText.value = "allFieldsReqMsg".tr;
      return;
    }
    _pipedServices
        .login(
            selectedInst.toString() == 'custom'
                ? instApiUrlInputController.text
                : selectedInst.toString(),
            userName,
            password)
        .then((res) {
      if (res.code == 1) {
        printINFO("Login Successfull");
        Get.find<SettingsScreenController>().isLinkedWithPiped.value = true;
        // Close the login dialog only if it is still up: the user may have
        // dismissed it while logging in, and popping then took Home away.
        if (Get.isDialogOpen == true) Navigator.of(Get.context!).pop();
        ScaffoldMessenger.of(Get.context!).showSnackBar(
            snackbar(Get.context!, "linkAlert".tr, size: SanckBarSize.MEDIUM));
        Get.find<LibraryPlaylistsController>().syncPipedPlaylist();
      } else {
        errorText.value = res.errorMessage ?? "errorOccuredAlert".tr;
      }
    });
  }

  @override
  void onClose() {
    instApiUrlInputController.dispose();
    usernameInputController.dispose();
    passwordInputController.dispose();
    super.onClose();
  }
}
