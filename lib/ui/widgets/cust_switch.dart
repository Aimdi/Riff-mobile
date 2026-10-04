import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';

class CustSwitch extends StatelessWidget {
  const CustSwitch({super.key, this.onChanged, required this.value});
  final void Function(bool)? onChanged;
  final bool value;

  @override
  Widget build(BuildContext context) {
    final isLightMode =
        Get.find<ThemeController>().themedata.value!.primaryColor ==
            Colors.white;
    final scheme = Theme.of(context).colorScheme;
    return Switch(
        activeColor: RiffColors.of(context).onImage,
        activeTrackColor: isLightMode ? scheme.outlineVariant : null,
        inactiveTrackColor: isLightMode ? scheme.outlineVariant : null,
        inactiveThumbColor: isLightMode
            ? scheme.surfaceContainerHigh
            : scheme.onSurface.withOpacity(0.5),
        value: value,
        onChanged: onChanged);
  }
}
