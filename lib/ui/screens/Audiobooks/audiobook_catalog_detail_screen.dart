import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/audiobook_catalog_service.dart';

/// Details for a commercial audiobook. Browse-only: it can't play in Riff
/// (Audible/DRM), so the actions open Audible / Apple Books to listen or buy.
class AudiobookCatalogDetailScreen extends StatefulWidget {
  const AudiobookCatalogDetailScreen({super.key, required this.book});
  final AudiobookItem book;

  @override
  State<AudiobookCatalogDetailScreen> createState() =>
      _AudiobookCatalogDetailScreenState();
}

class _AudiobookCatalogDetailScreenState
    extends State<AudiobookCatalogDetailScreen> {
  AudiobookDetails? _details;
  List<AudiobookItem> _similar = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final book = widget.book;
    final d = await AudiobookCatalogService.details(book.id);
    final sim = await AudiobookCatalogService.similar(
      author: book.author,
      genre: (d?.genre.isNotEmpty ?? false) ? d!.genre : book.genre,
      excludeId: book.id,
    );
    if (mounted) {
      setState(() {
        _details = d;
        _similar = sim;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final theme = Theme.of(context);
    // Prefer the richer looked-up values, fall back to what the grid had.
    final genre =
        (_details?.genre.isNotEmpty ?? false) ? _details!.genre : book.genre;
    final description = (_details?.description.isNotEmpty ?? false)
        ? _details!.description
        : book.description;

    return Scaffold(
      appBar: AppBar(title: Text(book.title, maxLines: 1)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: book.cover,
                width: 190,
                height: 190,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.menu_book, size: 120),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(book.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (book.author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(book.author,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge),
            ),
          const SizedBox(height: 12),
          // Fact chips: genre · year · rating · publisher
          _facts(theme, genre),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(book.audibleUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.headphones),
            label: Text('listenOnAudible'.tr),
          ),
          if ((_details?.appleUrl.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(_details!.appleUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.menu_book),
                label: Text('viewOnAppleBooks'.tr),
              ),
            ),
          const SizedBox(height: 8),
          Text('audiobookBrowseOnly'.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall),
          const Divider(height: 32),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ))
          else if (description.isNotEmpty)
            Text(description, style: theme.textTheme.bodyMedium)
          else
            Text('noDescription'.tr, style: theme.textTheme.bodySmall),
          if (_similar.isNotEmpty) _similarRow(theme),
        ],
      ),
    );
  }

  /// Horizontal strip of similar titles at the bottom; tap to open another book.
  Widget _similarRow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('similarTitles'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _similar.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final b = _similar[i];
              return SizedBox(
                width: 120,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Get.to(
                    () => AudiobookCatalogDetailScreen(book: b),
                    preventDuplicates: false,
                    transition: Transition.rightToLeft,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: b.cover,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.menu_book, size: 48),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        b.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (b.author.isNotEmpty)
                        Text(
                          b.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _facts(ThemeData theme, String genre) {
    final chips = <String>[
      if (genre.isNotEmpty) genre,
      if (_details?.releaseDate.isNotEmpty ?? false) _details!.releaseDate,
      if (_details?.rating.isNotEmpty ?? false) _details!.rating,
      if (_details?.publisher.isNotEmpty ?? false) _details!.publisher,
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: chips
          .map((c) => Chip(
                label: Text(c, style: theme.textTheme.bodySmall),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ))
          .toList(),
    );
  }
}
