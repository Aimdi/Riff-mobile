import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobook_downloads.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/confirm_dialog.dart';
import '/ui/widgets/riff_motion.dart';
import '/ui/widgets/snackbar.dart';

/// Download in a book's top bar, as Audible and the Audiobookshelf app have
/// it: the arrow downloads the book to listen offline; while it downloads,
/// how far it's got (a tap cancels); downloaded, a tap asks before removing
/// it from the phone.
class AudiobookDownloadButton extends StatelessWidget {
  const AudiobookDownloadButton({
    super.key,
    required this.bookId,
    required this.chapters,
  });

  final String bookId;

  /// The book's chapters, fresh from where it plays from.
  final List<MediaItem> Function() chapters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      AudiobookDownloads.rev.value;
      final at = AudiobookDownloads.progress[bookId];
      final downloaded = at == null && AudiobookDownloads.isDownloaded(bookId);
      // One button whose glyph crossfades between the three; the tick pops
      // in as the book finishes downloading.
      return IconButton(
        tooltip: at != null
            ? 'cancelDownload'.tr
            : downloaded
                ? 'removeDownload'.tr
                : 'download'.tr,
        onPressed: at != null
            ? () => AudiobookDownloads.cancel(bookId)
            : downloaded
                ? () => _remove(context)
                : () => _download(context),
        icon: RiffSwitcher(
          pop: downloaded,
          child: at != null
              ? SizedBox.square(
                  key: const ValueKey('progress'),
                  dimension: RiffComponentSizes.headerIcon,
                  // Waiting its turn (or for Wi-Fi): no amount yet.
                  child: CircularProgressIndicator(
                    value: at > 0 ? at : null,
                    strokeWidth: RiffComponentSizes.spinnerStroke,
                  ),
                )
              : downloaded
                  // Toggled-on = accent (§2.5).
                  ? Icon(Icons.download_done_rounded,
                      key: const ValueKey('done'),
                      size: RiffComponentSizes.headerIcon,
                      color: scheme.primary)
                  : Icon(Icons.download_for_offline_outlined,
                      key: const ValueKey('download'),
                      size: RiffComponentSizes.headerIcon,
                      color: scheme.onSurface),
        ),
      );
    });
  }

  Future<void> _download(BuildContext context) async {
    // The book page may be gone by the time it's done.
    final target = undoSnackbarTarget(context);
    List<MediaItem> items;
    try {
      items = chapters();
    } catch (_) {
      items = const [];
    }
    final result = await AudiobookDownloads.download(bookId, items);
    switch (result) {
      case BookDownload.done:
        showUndoSnackbar(target, 'downloadComplete'.tr);
      case BookDownload.failed:
        showUndoSnackbar(target, 'downloadFailed'.tr);
      case BookDownload.cancelled:
        break;
    }
  }

  Future<void> _remove(BuildContext context) async {
    final remove = await confirmDestructive(
      context,
      title: 'removeDownload'.tr,
      message: 'removeBookDownloadMsg'.tr,
      confirmLabel: 'remove'.tr,
    );
    if (remove) await AudiobookDownloads.remove(bookId);
  }
}
