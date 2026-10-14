import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_service.dart' show PodcastService;
import '/services/song_credits.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/common_dialog_widget.dart';
import 'song_info_dialog.dart' show InfoItem;

/// The song's credits, like Spotify's View credits: who performs it, each
/// role and who it credits, when it came out and its source, as YouTube's
/// notes for the track give them.
class SongCreditsDialog extends StatefulWidget {
  const SongCreditsDialog({super.key, required this.song});
  final MediaItem song;

  @override
  State<SongCreditsDialog> createState() => _SongCreditsDialogState();
}

class _SongCreditsDialogState extends State<SongCreditsDialog> {
  late Future<SongCredits?> _credits = SongCreditsService.load(widget.song.id);

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(
                left: RiffSpacing.xl,
                top: RiffSpacing.xxl,
                right: RiffSpacing.xl,
                bottom: RiffSpacing.md),
            child: RiffDialogTitle('credits'.tr,
                icon: Icons.groups_outlined, subtitle: widget.song.title),
          ),
          Flexible(
            child: FutureBuilder<SongCredits?>(
              future: _credits,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(RiffSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return _message(context, 'creditsLoadFailed'.tr,
                      retry: () => setState(() =>
                          _credits = SongCreditsService.load(widget.song.id)));
                }
                final credits = snap.data;
                if (credits == null || credits.isEmpty) {
                  return _message(context, 'noCredits'.tr);
                }
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: RiffSpacing.xs),
                  children: _items(credits),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
                left: RiffSpacing.xl,
                top: RiffSpacing.sm,
                right: RiffSpacing.xl,
                bottom: RiffSpacing.lg),
            child: RiffDialogButton('close'.tr,
                onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }

  List<Widget> _items(SongCredits c) {
    final released = c.released == null ? null : DateTime.tryParse(c.released!);
    return [
      if (c.performers.isNotEmpty)
        InfoItem(
            title: 'creditsPerformedBy'.tr, value: c.performers.join(', ')),
      for (final (role, names) in c.roles)
        InfoItem(title: role, value: names.join(', ')),
      if (c.released != null)
        InfoItem(
            title: 'creditsReleased'.tr,
            value: released == null
                ? c.released!
                : PodcastService.formatDay(released)),
      if (c.source != null)
        InfoItem(title: 'creditsSource'.tr, value: c.source!),
      if (c.providedBy != null)
        InfoItem(title: 'creditsProvidedBy'.tr, value: c.providedBy!),
    ];
  }

  Widget _message(BuildContext context, String text, {VoidCallback? retry}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RiffSpacing.xl, vertical: RiffSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (retry != null) ...[
            const SizedBox(height: RiffSpacing.sm),
            TextButton(onPressed: retry, child: Text('retry'.tr)),
          ],
        ],
      ),
    );
  }
}
