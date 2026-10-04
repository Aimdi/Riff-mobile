import '../Home/home_layout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobookshelf_service.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/song_list_tile.dart' show RiffRowHairline;
import 'audiobook_play.dart';

class AudiobookDetailScreen extends StatefulWidget {
  const AudiobookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  State<AudiobookDetailScreen> createState() => _AudiobookDetailScreenState();
}

class _AudiobookDetailScreenState extends State<AudiobookDetailScreen> {
  AbsBookDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Metadata only: openBook() starts a server play session, which Play
      // opens itself; calling it here orphaned one session per visit.
      final d = await Get.find<AudiobookshelfService>()
          .fetchBookDetail(widget.bookId);
      if (mounted) {
        setState(() {
          _detail = d;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Play from [index] (chapter tap), or resume when [index] is null
  /// (primary Play / Continue button).
  ///
  /// A locally stored position wins over the server's: it is the more recent
  /// truth on this device, since the server value lags by up to the sync
  /// interval. The ABS session position still covers a book that was listened
  /// to on another Audiobookshelf client.
  Future<void> _play({int? index}) async {
    if (_detail == null) return;
    await playAudiobook(bookId: widget.bookId, index: index);
  }

  @override
  Widget build(BuildContext context) {
    final abs = Get.find<AudiobookshelfService>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(children: [
        RiffPageHeader(_detail?.title ?? 'audiobooks'.tr),
        Expanded(
            child: _loading
                ? const SongListShimmer(itemCount: 8, topPadding: 12)
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(RiffSpacing.xxl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_outlined,
                                  size: RiffComponentSizes.rowArt,
                                  color: theme.colorScheme.error),
                              const SizedBox(height: RiffSpacing.md),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge),
                              const SizedBox(height: RiffSpacing.md),
                              TextButton(
                                  onPressed: _load, child: Text('retry'.tr)),
                            ],
                          ),
                        ),
                      )
                    : _buildBody(theme, abs)),
      ]),
    );
  }

  Widget _buildBody(ThemeData theme, AudiobookshelfService abs) {
    final d = _detail!;
    final cover = abs.coverUrl(d.id, width: 600);
    final canResume = d.currentTime > 5;
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.only(
          left: RiffSpacing.lg,
          top: RiffSpacing.sm,
          right: RiffSpacing.lg,
          bottom: RiffSpacing.listEnd),
      children: [
        // Show-page header (§ Phase 7): art radius 8, title headlineSmall,
        // author bodyMedium, Play as the primary pill.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RiffRadii.sm),
              child: CachedNetworkImage(
                imageUrl: cover,
                // Decode at display size, not full resolution.
                memCacheHeight: (RiffComponentSizes.bookCoverHeight *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
                width: RiffComponentSizes.bookCoverWidth,
                height: RiffComponentSizes.bookCoverHeight,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: RiffComponentSizes.bookCoverWidth,
                  height: RiffComponentSizes.bookCoverHeight,
                  color: scheme.surfaceContainerLow,
                  child: Icon(Icons.menu_book,
                      size: RiffComponentSizes.rowArt,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: RiffSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, style: theme.textTheme.headlineSmall),
                  if (d.author.isNotEmpty) ...[
                    const SizedBox(height: RiffSpacing.xs),
                    Text(d.author, style: theme.textTheme.bodyMedium),
                  ],
                  if (d.narrator != null && d.narrator!.isNotEmpty) ...[
                    const SizedBox(height: RiffSpacing.xxs),
                    Text(
                      '${'narrator'.tr}: ${d.narrator}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: RiffSpacing.md),
                  // No index: resume where the listener left off. The chapter
                  // rows below still pass an explicit index, because there the
                  // user picked the chapter deliberately.
                  FilledButton.icon(
                    onPressed: d.tracks.isEmpty ? null : () => _play(),
                    icon: Icon(canResume ? Icons.play_arrow : Icons.play_arrow),
                    label: Text(canResume ? 'continueListening'.tr : 'play'.tr),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (d.description != null && d.description!.isNotEmpty) ...[
          const SizedBox(height: RiffSpacing.lg),
          Text('description'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: RiffSpacing.xs),
          Text(d.description!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: RiffSpacing.xl),
        Text(
          '${'chapters'.tr} (${d.tracks.length})',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: RiffSpacing.sm),
        if (d.tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RiffSpacing.xxl),
            child: Text('absNoBooks'.tr, style: theme.textTheme.bodyMedium),
          )
        else
          ...List.generate(d.tracks.length, (i) {
            final t = d.tracks[i];
            final dur = t.duration > 0
                ? _fmt(Duration(milliseconds: (t.duration * 1000).round()))
                : '';
            // Episode-style row: titleMedium (2 lines), duration
            // bodyMedium, 20 dp secondary Play glyph, full-width hairline
            // inside the bottom edge.
            return Stack(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: RiffComponentSizes.chapterNumber / 2,
                    backgroundColor: scheme.surfaceContainerLow,
                    child: Text('${i + 1}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  title: Text(t.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: dur.isEmpty ? null : Text(dur),
                  trailing: IconButton(
                    color: scheme.onSurfaceVariant,
                    icon: const Icon(Icons.play_arrow,
                        size: RiffComponentSizes.trailingIcon),
                    onPressed: () => _play(index: i),
                  ),
                  onTap: () => _play(index: i),
                ),
                const RiffRowHairline(),
              ],
            );
          }),
      ],
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
