import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';

/// Spotify's green arrow: a song saved for offline shows a small filled
/// download mark before its artist, in the accent (an on state). It comes
/// as the download finishes and goes when the download is deleted. Read as
/// "Downloaded".
class DownloadedMark extends StatefulWidget {
  const DownloadedMark({super.key, required this.songId});

  final String songId;

  @override
  State<DownloadedMark> createState() => _DownloadedMarkState();
}

class _DownloadedMarkState extends State<DownloadedMark> {
  static const _box = 'SongDownloads';

  /// Changes to this song's download only.
  ValueListenable<Box>? _download;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(DownloadedMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) _listen();
  }

  void _listen() {
    _download = Hive.isBoxOpen(_box)
        ? Hive.box(_box).listenable(keys: [widget.songId])
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final download = _download;
    if (download == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Box>(
      valueListenable: download,
      // The mark fades in as the room for it opens, so the artist glides
      // over rather than jumping (and back as it goes). Keyed by the song:
      // a row reused for another song doesn't animate.
      builder: (context, box, _) => AnimatedSize(
        key: ValueKey(widget.songId),
        duration: RiffDurations.select,
        curve: RiffDurations.selectCurve,
        alignment: AlignmentDirectional.centerStart,
        child: RiffSwitcher(
          alignment: AlignmentDirectional.centerStart,
          child: !box.containsKey(widget.songId)
              ? const SizedBox.shrink(key: ValueKey(false))
              : Padding(
                  key: const ValueKey(true),
                  padding: const EdgeInsets.only(right: RiffSpacing.xs),
                  child: Icon(
                    Icons.download_for_offline_rounded,
                    size: RiffComponentSizes.downloadedMark,
                    color: Theme.of(context).colorScheme.primary,
                    semanticLabel: 'downloaded'.tr,
                  ),
                ),
        ),
      ),
    );
  }
}
