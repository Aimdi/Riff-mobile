import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobookshelf_service.dart';
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
      final d = await Get.find<AudiobookshelfService>().openBook(widget.bookId);
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
      appBar: AppBar(
        title: Text(_detail?.title ?? 'audiobooks'.tr),
        backgroundColor: theme.canvasColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined,
                            size: 48,
                            color: theme.colorScheme.error.withOpacity(0.8)),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: Text('retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _buildBody(theme, abs),
    );
  }

  Widget _buildBody(ThemeData theme, AudiobookshelfService abs) {
    final d = _detail!;
    final cover = abs.coverUrl(d.id, width: 600);
    final canResume = d.currentTime > 5;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 200),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: cover,
                width: 120,
                height: 180,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 120,
                  height: 180,
                  color: theme.primaryColorLight,
                  child: const Icon(Icons.menu_book, size: 40),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, style: theme.textTheme.titleLarge),
                  if (d.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(d.author, style: theme.textTheme.titleSmall),
                  ],
                  if (d.narrator != null && d.narrator!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${'narrator'.tr}: ${d.narrator}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 10),
                  // No index: resume where the listener left off. The chapter
                  // rows below still pass an explicit index, because there the
                  // user picked the chapter deliberately.
                  ElevatedButton.icon(
                    onPressed: d.tracks.isEmpty ? null : () => _play(),
                    icon: Icon(canResume ? Icons.play_arrow : Icons.play_arrow),
                    label: Text(canResume
                        ? 'continueListening'.tr
                        : 'play'.tr),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (d.description != null && d.description!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('description'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(d.description!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 20),
        Text(
          '${'chapters'.tr} (${d.tracks.length})',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (d.tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('absNoBooks'.tr,
                style: theme.textTheme.bodyMedium),
          )
        else
          ...List.generate(d.tracks.length, (i) {
            final t = d.tracks[i];
            final dur = t.duration > 0
                ? _fmt(Duration(milliseconds: (t.duration * 1000).round()))
                : '';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
              ),
              title:
                  Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: dur.isEmpty ? null : Text(dur),
              trailing: IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _play(index: i),
              ),
              onTap: () => _play(index: i),
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
