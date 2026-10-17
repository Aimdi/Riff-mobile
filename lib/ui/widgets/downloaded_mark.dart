import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

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
      builder: (context, box, _) {
        if (!box.containsKey(widget.songId)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: RiffSpacing.xs),
          child: Icon(
            Icons.download_for_offline_rounded,
            size: RiffComponentSizes.downloadedMark,
            color: Theme.of(context).colorScheme.primary,
            semanticLabel: 'downloaded'.tr,
          ),
        );
      },
    );
  }
}
