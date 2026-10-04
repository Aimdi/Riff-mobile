import '../Home/home_layout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/audiobook_catalog_service.dart';
import '/services/plugin_service.dart';
import '/ui/screens/Plugins/torrent_search_screen.dart';
import '/ui/theme/palettes/audiobook_rating.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
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
      body: Column(children: [
        RiffPageHeader(book.title, actions: [
          Obx(() {
            final isSaved = lib.saved.any((b) => b.id == book.id);
            return IconButton(
              tooltip: isSaved ? 'saved'.tr : 'save'.tr,
              // Toggled on = filled accent glyph (§4.6).
              icon: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border_rounded,
                  color: isSaved ? theme.colorScheme.primary : null),
              onPressed: () => lib.toggle(book),
            );
          }),
        ]),
        Expanded(
            child: ListView(
          padding: const EdgeInsets.only(
              left: RiffSpacing.lg,
              top: RiffSpacing.md,
              right: RiffSpacing.lg,
              bottom: RiffSpacing.unit * 10),
          children: [
            // Show-page header (§ Phase 7): art radius 8, title
            // headlineSmall, author bodyMedium (a link here, so the accent).
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RiffRadii.sm),
                child: CachedNetworkImage(
                  imageUrl: book.cover,
                  // Decode at display size, not full resolution.
                  // Store audiobook art is square.
                  memCacheHeight: (RiffComponentSizes.storeBookCover *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  width: RiffComponentSizes.storeBookCover,
                  height: RiffComponentSizes.storeBookCover,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(Icons.menu_book,
                      size: RiffComponentSizes.storeBookCover * 0.6,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(height: RiffSpacing.lg),
            Text(book.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall),
            if (book.author.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: RiffSpacing.xs),
                child: InkWell(
                  borderRadius: BorderRadius.circular(RiffRadii.xs),
                  onTap: () => Get.to(
                    () => AudiobookBrowseScreen(
                        title: book.author, query: book.author),
                    transition: Transition.rightToLeft,
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: RiffSpacing.xxs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            book.author,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: RiffSpacing.xxs),
                        Icon(Icons.chevron_right,
                            size: RiffComponentSizes.chipChevron,
                            color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            if (_rating != null) ...[
              const SizedBox(height: RiffSpacing.sm),
              _starRow(theme, _rating!),
            ],
            const SizedBox(height: RiffSpacing.md),
            // Fact chips: genre · year · rating · publisher
            _facts(theme, genre),
            const SizedBox(height: RiffSpacing.lg),
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
                padding: const EdgeInsets.only(top: RiffSpacing.sm),
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
                  .isInstalled(PluginIds.torrentSearch);
              if (!hasTorrents) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: RiffSpacing.sm),
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Detail was opened with Get.to (root stack). Push torrent
                    // search on the same stack — nested toNamed is invisible here.
                    final query = [
                      if (book.author.trim().isNotEmpty) book.author.trim(),
                      book.title.trim(),
                    ].join(' ').trim();
                    Get.to(
                      () => TorrentSearchScreen(
                        initialQuery: query.isEmpty ? null : query,
                      ),
                      transition: Transition.rightToLeft,
                    );
                  },
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text('searchTorrents'.tr),
                ),
              );
            }),
            const SizedBox(height: RiffSpacing.sm),
            Text('audiobookBrowseOnly'.tr,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const Divider(height: RiffSpacing.x3l),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(RiffSpacing.md),
                child: SizedBox(
                    width: RiffComponentSizes.spinner,
                    height: RiffComponentSizes.spinner,
                    child: CircularProgressIndicator(
                        strokeWidth: RiffComponentSizes.spinnerStroke)),
              ))
            else if (description.isNotEmpty)
              Text(description, style: theme.textTheme.bodyLarge)
            else
              Text('noDescription'.tr, style: theme.textTheme.bodyMedium),
            if (_similar.isNotEmpty) _similarRow(theme),
          ],
        )),
      ]),
    );
  }

  /// Horizontal strip of similar titles at the bottom; tap to open another book.
  Widget _similarRow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: RiffSpacing.xxl),
        Text('similarTitles'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: RiffSpacing.md),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _similar.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: RiffSpacing.cardGap),
            itemBuilder: (context, i) {
              final b = _similar[i];
              // §5.3 shelf card: no background, art radius 8, titleMedium /
              // bodyMedium, art → title gap 8.
              return SizedBox(
                width: RiffComponentSizes.bookCoverWidth,
                child: InkWell(
                  borderRadius: BorderRadius.circular(RiffRadii.sm),
                  onTap: () => Get.to(
                    () => AudiobookCatalogDetailScreen(book: b),
                    preventDuplicates: false,
                    transition: Transition.rightToLeft,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(RiffRadii.sm),
                        child: CachedNetworkImage(
                          imageUrl: b.cover,
                          // Decode at display size, not full resolution.
                          memCacheHeight: (RiffComponentSizes.bookCoverHeight *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                          width: RiffComponentSizes.bookCoverWidth,
                          height: RiffComponentSizes.bookCoverHeight,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(Icons.menu_book,
                              size: RiffComponentSizes.rowArt,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: RiffSpacing.sm),
                      Text(
                        b.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (b.author.isNotEmpty)
                        Text(
                          b.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
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
    const amber = AudiobookRatingPalette.star;
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
            size: RiffComponentSizes.trailingIcon,
            color: amber,
          ),
        const SizedBox(width: RiffSpacing.sm),
        Text(
          r.average.toStringAsFixed(1),
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurface),
        ),
        if (r.count > 0)
          Text(
            '  ·  ${r.count} ${'ratings'.tr}',
            style: theme.textTheme.bodyMedium,
          ),
      ],
    );
  }

  Widget _facts(ThemeData theme, String genre) {
    // Tappable "browse" chips (genre, extra subject tags, year) + static chips
    // (content rating, publisher).
    final year = (_details?.releaseDate.isNotEmpty ?? false)
        ? _details!.releaseDate
        : '';
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
    // §5.6 chips from the chip theme (transparent, divider hairline,
    // labelMedium); glyphs in the secondary colour.
    Widget browseChip(String label, IconData icon, String query) => ActionChip(
          avatar: Icon(icon,
              size: RiffComponentSizes.chipLeadingIcon,
              color: theme.colorScheme.onSurfaceVariant),
          label: Text(label),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: () => Get.to(
            () => AudiobookBrowseScreen(title: label, query: query),
            transition: Transition.rightToLeft,
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: RiffSpacing.sm,
      runSpacing: RiffSpacing.sm,
      children: [
        for (final t in tags) browseChip(t, Icons.local_offer_outlined, t),
        // Year → browse titles from that year in this genre (best-effort).
        if (year.isNotEmpty)
          browseChip(year, Icons.event_outlined,
              genre.isNotEmpty ? '$genre $year' : year),
        ...plain.map((c) => Chip(
              label: Text(c),
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
      body: Column(children: [
        RiffPageHeader(widget.title),
        Expanded(
            child: _loading
                ? const SongListShimmer(itemCount: 8, topPadding: 12)
                : _books.isEmpty
                    ? Center(child: Text('noResults'.tr))
                    : GridView.builder(
                        padding: const EdgeInsets.only(
                            left: RiffSpacing.md,
                            top: RiffSpacing.md,
                            right: RiffSpacing.md,
                            bottom: RiffSpacing.unit * 10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.56,
                          crossAxisSpacing: RiffSpacing.md,
                          mainAxisSpacing: RiffSpacing.md,
                        ),
                        itemCount: _books.length,
                        itemBuilder: (context, i) {
                          final book = _books[i];
                          // §5.3 card: no background, art radius 8,
                          // titleMedium / bodyMedium, art → title gap 8.
                          return InkWell(
                            borderRadius: BorderRadius.circular(RiffRadii.sm),
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
                                    borderRadius:
                                        BorderRadius.circular(RiffRadii.sm),
                                    child: CachedNetworkImage(
                                      imageUrl: book.cover,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(
                                        color: theme
                                            .colorScheme.surfaceContainerLow,
                                        child: Icon(Icons.menu_book,
                                            size: RiffComponentSizes.rowArt,
                                            color: theme
                                                .colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: RiffSpacing.sm),
                                Text(book.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium),
                                if (book.author.isNotEmpty)
                                  Text(book.author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium),
                              ],
                            ),
                          );
                        },
                      )),
      ]),
    );
  }
}
