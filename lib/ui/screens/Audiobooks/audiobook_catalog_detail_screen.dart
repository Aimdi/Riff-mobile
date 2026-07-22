import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/audiobook_catalog_service.dart';
import '/services/plugin_service.dart';
import '/ui/navigator.dart';
import 'audiobook_library_controller.dart';

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
  AudiobookRating? _rating;
  List<String> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final book = widget.book;
    // Rating + tags (Google Books) — fetch alongside the iTunes details.
    final extrasFuture =
        AudiobookCatalogService.extras(title: book.title, author: book.author);
    final d = await AudiobookCatalogService.details(book.id);
    final sim = await AudiobookCatalogService.similar(
      author: book.author,
      genre: (d?.genre.isNotEmpty ?? false) ? d!.genre : book.genre,
      excludeId: book.id,
    );
    final extras = await extrasFuture;
    if (mounted) {
      setState(() {
        _details = d;
        _similar = sim;
        _rating = extras.rating;
        _categories = extras.categories;
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

    final lib = Get.find<AudiobookLibraryController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1),
        actions: [
          Obx(() {
            final isSaved = lib.saved.any((b) => b.id == book.id);
            return IconButton(
              tooltip: isSaved ? 'saved'.tr : 'save'.tr,
              icon: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border_rounded),
              onPressed: () => lib.toggle(book),
            );
          }),
        ],
      ),
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
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => Get.to(
                  () => AudiobookBrowseScreen(
                      title: book.author, query: book.author),
                  transition: Transition.rightToLeft,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          book.author,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right,
                          size: 18, color: theme.colorScheme.secondary),
                    ],
                  ),
                ),
              ),
            ),
          if (_rating != null) ...[
            const SizedBox(height: 8),
            _starRow(theme, _rating!),
          ],
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
          Obx(() {
            final hasTorrents = Get.find<PluginService>()
                .isInstalled(PluginIds.torrentsDigger);
            if (!hasTorrents) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => Get.toNamed(
                  ScreenNavigationSetup.torrentSearchScreen,
                  id: ScreenNavigationSetup.id,
                ),
                icon: const Icon(Icons.travel_explore_outlined),
                label: Text('searchTorrents'.tr),
              ),
            );
          }),
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

  /// Centered 5-star row (full/half/empty) + numeric average and rating count.
  Widget _starRow(ThemeData theme, AudiobookRating r) {
    const amber = Color(0xFFFFB300);
    final full = r.average.floor();
    final hasHalf = (r.average - full) >= 0.25 && (r.average - full) < 0.75;
    final roundedUp = (r.average - full) >= 0.75;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < 5; i++)
          Icon(
            i < full || (i == full && roundedUp)
                ? Icons.star_rounded
                : (i == full && hasHalf)
                    ? Icons.star_half_rounded
                    : Icons.star_border_rounded,
            size: 20,
            color: amber,
          ),
        const SizedBox(width: 6),
        Text(
          r.average.toStringAsFixed(1),
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (r.count > 0)
          Text(
            '  ·  ${r.count} ${'ratings'.tr}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _facts(ThemeData theme, String genre) {
    // Tappable "browse" chips (genre, extra subject tags, year) + static chips
    // (content rating, publisher).
    final year =
        (_details?.releaseDate.isNotEmpty ?? false) ? _details!.releaseDate : '';
    // Genre + Google Books subjects, de-duplicated (case-insensitive).
    final tags = <String>[];
    final seen = <String>{};
    for (final t in [if (genre.isNotEmpty) genre, ..._categories]) {
      final key = t.toLowerCase();
      if (seen.add(key)) tags.add(t);
    }
    final plain = <String>[
      if (_details?.rating.isNotEmpty ?? false) _details!.rating,
      if (_details?.publisher.isNotEmpty ?? false) _details!.publisher,
    ];
    if (tags.isEmpty && year.isEmpty && plain.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget browseChip(String label, IconData icon, String query) => ActionChip(
          avatar: Icon(icon, size: 15, color: theme.colorScheme.secondary),
          label: Text(label, style: theme.textTheme.bodySmall),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: () => Get.to(
            () => AudiobookBrowseScreen(title: label, query: query),
            transition: Transition.rightToLeft,
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final t in tags)
          browseChip(t, Icons.local_offer_outlined, t),
        // Year → browse titles from that year in this genre (best-effort).
        if (year.isNotEmpty)
          browseChip(year, Icons.event_outlined,
              genre.isNotEmpty ? '$genre $year' : year),
        ...plain.map((c) => Chip(
              label: Text(c, style: theme.textTheme.bodySmall),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )),
      ],
    );
  }
}

/// Browse the catalog for a query (a genre, subject tag, author or year),
/// tapped from a book's detail page.
class AudiobookBrowseScreen extends StatefulWidget {
  const AudiobookBrowseScreen(
      {super.key, required this.title, required this.query});
  final String title;
  final String query;

  @override
  State<AudiobookBrowseScreen> createState() => _AudiobookBrowseScreenState();
}

class _AudiobookBrowseScreenState extends State<AudiobookBrowseScreen> {
  List<AudiobookItem> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await AudiobookCatalogService.search(widget.query);
    if (mounted) {
      setState(() {
        _books = res;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? Center(child: Text('noResults'.tr))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _books.length,
                  itemBuilder: (context, i) {
                    final book = _books[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Get.to(
                        () => AudiobookCatalogDetailScreen(book: book),
                        preventDuplicates: false,
                        transition: Transition.rightToLeft,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: book.cover,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: theme.primaryColorLight,
                                  child: const Icon(Icons.menu_book, size: 48),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          if (book.author.isNotEmpty)
                            Text(book.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
