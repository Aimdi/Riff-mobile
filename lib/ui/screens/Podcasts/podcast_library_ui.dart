import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '/services/opml.dart';
import '/ui/theme/riff_spacing.dart';
import '/services/podcast_library.dart';
import '/services/podcast_service.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/snackbar.dart';
import '../Home/home_layout.dart';

String _keepLabel(int n) => n <= 0 ? 'keepAll'.tr : '$n';
String _autoDeleteLabel(AutoDeletePolicy p) => 'autoDelete_${p.name}'.tr;

/// Keep latest + auto-delete choices, as chips. With [showKey] it edits that
/// show (with a "Default" chip); without, the defaults in Podcast settings.
class PodcastLibraryEditor extends StatelessWidget {
  const PodcastLibraryEditor({super.key, this.showKey});
  final String? showKey;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      PodcastLibrary.rev.value;
      final key = showKey;
      final keepOverride =
          key == null ? null : PodcastLibrary.keepOverride(key);
      final keep = key == null
          ? PodcastLibrary.defaultKeepLatest
          : PodcastLibrary.keepLatestFor(key);
      final delOverride =
          key == null ? null : PodcastLibrary.autoDeleteOverride(key);
      final del = key == null
          ? PodcastLibrary.defaultAutoDelete
          : PodcastLibrary.autoDeleteFor(key);
      final titleStyle = Theme.of(context).textTheme.titleMedium;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('keepLatest'.tr, style: titleStyle),
          const SizedBox(height: 2),
          Text('keepLatestDes'.tr, style: homeCardSubtitleStyle(context)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (key != null)
                RiffChoiceChip(
                  label: 'useDefault'.trParams(
                      {'value': _keepLabel(PodcastLibrary.defaultKeepLatest)}),
                  selected: keepOverride == null,
                  onTap: () => PodcastLibrary.setShowKeepLatest(key, null),
                ),
              for (final n in keepLatestChoices)
                RiffChoiceChip(
                  label: _keepLabel(n),
                  selected: (key == null || keepOverride != null) && keep == n,
                  onTap: () => key == null
                      ? PodcastLibrary.setDefaultKeepLatest(n)
                      : PodcastLibrary.setShowKeepLatest(key, n),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text('autoDelete'.tr, style: titleStyle),
          const SizedBox(height: 2),
          Text('autoDeleteDes'.tr, style: homeCardSubtitleStyle(context)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (key != null)
                RiffChoiceChip(
                  label: 'useDefault'.trParams({
                    'value': _autoDeleteLabel(PodcastLibrary.defaultAutoDelete)
                  }),
                  selected: delOverride == null,
                  onTap: () => PodcastLibrary.setShowAutoDelete(key, null),
                ),
              for (final p in AutoDeletePolicy.values)
                RiffChoiceChip(
                  label: _autoDeleteLabel(p),
                  selected: (key == null || delOverride != null) && del == p,
                  onTap: () => key == null
                      ? PodcastLibrary.setDefaultAutoDelete(p)
                      : PodcastLibrary.setShowAutoDelete(key, p),
                ),
            ],
          ),
        ],
      );
    });
  }
}

/// Show page ⋮ › Episodes and downloads.
Future<void> showPodcastShowLibrarySheet(BuildContext context,
    {required String showKey, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: riffSheetShape,
    builder: (sheet) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('showLibrarySettings'.tr, subtitle: title),
            Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.xl,
                  top: RiffSpacing.sm,
                  right: RiffSpacing.xl),
              child: PodcastLibraryEditor(showKey: showKey),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Show page ⋮ › Mark all as listened, with Undo.
void markShowListened(BuildContext context, List<MediaItem> episodes,
    {VoidCallback? onChanged}) {
  final snap = PodcastLibrary.markAllListened(episodes);
  onChanged?.call();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(snap.count == 0
          ? 'nothingToMark'.tr
          : 'markedAllListened'.trParams({'count': '${snap.count}'})),
      action: snap.count == 0
          ? null
          : SnackBarAction(
              label: 'undo'.tr,
              onPressed: () async {
                await PodcastLibrary.undoMarkAll(snap);
                onChanged?.call();
              },
            ),
    ));
}

// ── OPML ──────────────────────────────────────────────────────────────

/// Feed subscriptions as OPML entries.
List<OpmlFeed> currentOpmlFeeds() => [
      for (final s in PodcastService.subscriptions)
        if ('${s['feedUrl'] ?? ''}'.isNotEmpty)
          OpmlFeed(feedUrl: '${s['feedUrl']}', title: '${s['title'] ?? ''}')
    ];

/// Follow the feeds in an OPML file the user picks.
Future<void> importOpml(BuildContext context) async {
  void snack(String m) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(snackbar(context, m, size: SanckBarSize.BIG));
  }

  final FilePickerResult? res;
  try {
    res = await FilePicker.platform.pickFiles(
        type: FileType.any, withData: true, dialogTitle: 'opmlImport'.tr);
  } catch (_) {
    snack('operationFailed'.tr);
    return;
  }
  if (res == null || res.files.isEmpty) return;
  final f = res.files.single;
  String text;
  try {
    text = f.bytes != null
        ? utf8.decode(f.bytes!, allowMalformed: true)
        : await File(f.path!).readAsString();
  } catch (_) {
    snack('operationFailed'.tr);
    return;
  }
  final feeds = parseOpml(text);
  if (feeds.isEmpty) {
    snack('opmlNothing'.tr);
    return;
  }
  var added = 0;
  for (final feed in feeds) {
    if (PodcastService.isSubscribed(feed.feedUrl)) continue;
    await PodcastService.subscribe({
      'feedUrl': feed.feedUrl,
      'title': feed.title,
      'author': '',
      'artwork': '',
    });
    added++;
  }
  // Covers for the new shows, in the background.
  if (added > 0) PodcastService.refreshMissingArtwork();
  snack('opmlImported'
      .trParams({'added': '$added', 'skipped': '${feeds.length - added}'}));
}

/// Share the feed subscriptions as an OPML file.
Future<void> exportOpml(BuildContext context) async {
  final feeds = currentOpmlFeeds();
  if (feeds.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'opmlExportEmpty'.tr, size: SanckBarSize.BIG));
    return;
  }
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/riff-podcasts.opml');
    await file.writeAsString(buildOpml(feeds));
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'text/x-opml', name: 'riff-podcasts.opml')
    ]);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, 'operationFailed'.tr, size: SanckBarSize.BIG));
    }
  }
}

/// Podcast settings › Episodes and downloads + Import and export.
class PodcastLibrarySettings extends StatelessWidget {
  const PodcastLibrarySettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('podcastLibraryDefaults'.tr,
            style: homeSectionTitleStyle(context)),
        const SizedBox(height: 4),
        Text('podcastLibraryDefaultsDes'.tr,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: homeMutedColor(context))),
        const SizedBox(height: 14),
        const PodcastLibraryEditor(),
        const SizedBox(height: 28),
        Text('opmlTitle'.tr, style: homeSectionTitleStyle(context)),
        const SizedBox(height: 4),
        Text('opmlDes'.tr,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: homeMutedColor(context))),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            RiffChoiceChip(
              icon: Icons.file_download_outlined,
              label: 'opmlImport'.tr,
              onTap: () => importOpml(context),
            ),
            RiffChoiceChip(
              icon: Icons.ios_share_rounded,
              label: 'opmlExport'.tr,
              onTap: () => exportOpml(context),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('opmlExportNote'.tr, style: homeCardSubtitleStyle(context)),
      ],
    );
  }
}
