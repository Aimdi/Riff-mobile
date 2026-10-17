import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_item_extras.dart';
import '/services/explicit_content.dart';
import '/services/offline_playback.dart';
import '/ui/theme/riff_tokens.dart';

/// [song]'s row, dimmed while it won't play, as Spotify greys out what
/// can't: an explicit song while explicit content is off, or one that
/// needs a connection while there's none.
class UnplayableDim extends StatelessWidget {
  const UnplayableDim({super.key, required this.song, required this.child});

  final MediaItem song;
  final Widget child;

  @override
  Widget build(BuildContext context) => Obx(() {
        // Both read each time, so the row follows either.
        final explicitOff = !ExplicitContent.allowed.value;
        final offline = OfflinePlayback.offline.value;
        final unplayable = (explicitOff && song.isExplicit) ||
            (offline && OfflinePlayback.needsConnection(song));
        return Opacity(
          opacity: unplayable ? RiffPalette.unavailableOpacity : 1,
          child: child,
        );
      });
}
