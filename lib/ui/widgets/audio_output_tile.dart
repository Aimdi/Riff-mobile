import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audio_output.dart';
import 'riff_sheet.dart';

/// "Play on another device", a row of the players' ⋮ sheets: closes the
/// sheet and opens the phone's own output switcher (headphones, a speaker,
/// this phone), as Spotify's and YouTube Music's devices button does.
/// Nothing where there's none (off Android).
class AudioOutputTile extends StatelessWidget {
  const AudioOutputTile({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AudioOutput.available) return const SizedBox.shrink();
    return RiffSheetTile(
      icon: Icons.speaker_group_rounded,
      title: 'playOn'.tr,
      onTap: () {
        Navigator.of(context).pop();
        AudioOutput.showSwitcher();
      },
    );
  }
}
