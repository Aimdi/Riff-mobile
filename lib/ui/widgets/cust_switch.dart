import 'package:flutter/material.dart';

/// The app's on/off switch. Colours come from the theme's `switchTheme`
/// (RIFF_UI_RESTYLE.md §5.9: accent track / onAccent thumb when on,
/// surface2 track / outlineStrong outline / textSecondary thumb when off).
class CustSwitch extends StatelessWidget {
  const CustSwitch({super.key, this.onChanged, required this.value});
  final void Function(bool)? onChanged;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return Switch(value: value, onChanged: onChanged);
  }
}
