import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/voice_input.dart';
import '/ui/theme/riff_tokens.dart';

/// The search field's mic, as in YouTube Music, Spotify and Apple Music:
/// the phone listens and [onHeard] gets what it heard. Nothing where the
/// phone can't listen (no speech recognition, not Android).
class VoiceSearchButton extends StatelessWidget {
  const VoiceSearchButton({super.key, required this.onHeard});

  final ValueChanged<String> onHeard;

  Future<void> _listen(BuildContext context) async {
    final heard = await VoiceInput.listen(prompt: 'voiceSearchPrompt'.tr);
    if (heard != null && context.mounted) onHeard(heard);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: VoiceInput.available(),
        // Back after the field was cleared: no blank frame first.
        initialData: VoiceInput.known,
        builder: (context, snapshot) => snapshot.data == true
            ? IconButton(
                tooltip: 'voiceSearch'.tr,
                onPressed: () => _listen(context),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(RiffComponentSizes.iconHit),
                ),
                icon: const Icon(Icons.mic_none_rounded,
                    size: RiffComponentSizes.trailingIcon),
              )
            : const SizedBox.shrink(),
      );
}
