import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;

import '/ui/screens/Playlist/playlist_screen_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'common_dialog_widget.dart';
import 'snackbar.dart';

class PlaylistExportDialog extends StatelessWidget {
  const PlaylistExportDialog({
    super.key,
    required this.controller,
    required this.parentContext,
  });

  final PlaylistScreenController controller;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Container(
        padding: const EdgeInsets.all(RiffSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.only(
                  bottom: RiffSpacing.lg, top: RiffSpacing.xs),
              child: RiffDialogTitle("exportPlaylist".tr,
                  icon: Icons.ios_share_rounded),
            ),
            // Button 1: Export to JSON
            _ExportButton(
              icon: Icons.data_object_rounded,
              title: "exportPlaylistJson".tr,
              subtitle: "exportPlaylistJsonSubtitle".tr,
              onTap: () {
                Navigator.of(context).pop();
                controller.exportPlaylistToJson(parentContext);
              },
            ),
            const SizedBox(height: RiffSpacing.md),
            // Button 2: Export to CSV
            _ExportButton(
              icon: Icons.table_chart_outlined,
              title: "exportPlaylistCsv".tr,
              subtitle: "exportPlaylistCsvSubtitle".tr,
              onTap: () {
                Navigator.of(context).pop();
                controller.exportPlaylistToCsv(parentContext);
              },
            ),
            const SizedBox(height: RiffSpacing.md),
            // Button 3: Export to YouTube Music (split button)
            _SplitExportButton(
              icon: Icons.open_in_new,
              title: "exportToYouTubeMusic".tr,
              subtitle: "exportToYouTubeMusicSubtitle".tr,
              onMainTap: () {
                Navigator.of(context).pop();
                _openInYouTubeMusic();
              },
              onCopyTap: () {
                Navigator.of(context).pop();
                _copyYouTubeMusicLink();
              },
            ),
            const SizedBox(height: RiffSpacing.md),
            RiffDialogButton("close".tr,
                primary: false, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  Future<void> _openInYouTubeMusic() async {
    final videoIds = controller.songList.map((song) => song.id).join(',');
    final url = 'https://www.youtube.com/watch_videos?video_ids=$videoIds';
    final ytmUrl = await _generateYTMUrl(url);

    launchUrl(
      Uri.parse(ytmUrl ?? url),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<String?> _generateYTMUrl(String ytSimpleUrl) async {
    if (controller.generatedYtmPlaylistUrl.isNotEmpty) {
      return controller.generatedYtmPlaylistUrl;
    }

    try {
      final x = (await Dio().get(ytSimpleUrl)).data;
      final document = html_parser.parse(x);

      // Find the <link> element with rel="canonical"
      final canonicalLink = document.querySelector('link[rel="canonical"]');

      // Extract its href attribute
      String? href = canonicalLink?.attributes['href'];
      href = href?.replaceAll('www', 'music');
      if (href != null) {
        controller.generatedYtmPlaylistUrl = href;
        return href;
      }
      // ignore: empty_catches
    } catch (e) {}
    return null;
  }

  Future<void> _copyYouTubeMusicLink() async {
    final videoIds = controller.songList.map((song) => song.id).join(',');
    final url = 'https://www.youtube.com/watch_videos?video_ids=$videoIds';
    final ytmUrl = await _generateYTMUrl(url);

    Clipboard.setData(ClipboardData(text: ytmUrl ?? url)).then((_) {
      if (parentContext.mounted) {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          snackbar(
            parentContext,
            "linkCopied".tr,
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
    });
  }
}

/// Icon, title and subtitle of one export option. Text stays in the
/// primary colour on the raised tile (§5.11 contrast); the icon box is
/// unfilled (the accent is kept for interactive things).
class _OptionLabel extends StatelessWidget {
  const _OptionLabel(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return Row(
      children: [
        SizedBox(
          width: RiffComponentSizes.iconHit,
          height: RiffComponentSizes.iconHit,
          child: Icon(icon, color: fg, size: RiffComponentSizes.sheetIcon),
        ),
        const SizedBox(width: RiffSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(color: fg)),
              const SizedBox(height: RiffSpacing.xxs),
              Text(subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      // One step above the dialog's surface1, flat, radius 8.
      color: RiffColors.of(context).surface2,
      borderRadius: BorderRadius.circular(RiffRadii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(RiffSpacing.md),
          child: _OptionLabel(icon: icon, title: title, subtitle: subtitle),
        ),
      ),
    );
  }
}

class _SplitExportButton extends StatelessWidget {
  const _SplitExportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onMainTap,
    required this.onCopyTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onMainTap;
  final VoidCallback onCopyTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RiffColors.of(context).surface2,
      borderRadius: BorderRadius.circular(RiffRadii.sm),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onMainTap,
                child: Padding(
                  padding: const EdgeInsets.all(RiffSpacing.md),
                  child: _OptionLabel(
                      icon: icon, title: title, subtitle: subtitle),
                ),
              ),
            ),
            // Hairline (§5.1).
            VerticalDivider(
              width: 1,
              thickness: 0,
              indent: RiffSpacing.md,
              endIndent: RiffSpacing.md,
              color: Theme.of(context).dividerColor,
            ),
            InkWell(
              onTap: onCopyTap,
              child: SizedBox(
                width: RiffComponentSizes.splitAction,
                child: Icon(Icons.copy_rounded,
                    size: RiffComponentSizes.trailingIcon,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
